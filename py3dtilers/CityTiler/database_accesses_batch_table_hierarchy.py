import itertools

from py3dtiles import BatchTableHierarchy
from ..Common import TreeWithChildrenAndParent


def retrieve_buildings_and_sub_parts(cursor, buildingIds, classes, hierarchy):
    """
    :type classes: new classes are appended
    """
    # ##### Walk on the building and
    #   - collect buildings': id, glm-id and class
    #   - collect the names of used classes (i.e. the types of user data)
    #   - collect the hierarchical information
    buildindsAndSubParts = []

    cursor.execute(
        "SELECT building.id, building_parent_id,"
        "       cityobject.gmlid, cityobject.objectclass_id "
        "FROM citydb.building JOIN citydb.cityobject ON building.id=cityobject.id "
        "                        WHERE building_root_id IN " + buildingIds)
    for t in cursor.fetchall():
        buildindsAndSubParts.append(
            {'internalId': t[0], 'gmlid': t[2], 'class': t[3]})
        hierarchy.addNodeToParent(t[0], t[1])
        # Note: set.add() does nothing when the added element is already
        # present in the set
        classes.add(t[3])
    return buildindsAndSubParts


def retrieve_geometric_instances(cursor, buildingIds, classes, hierarchy):
    """
    :type classes: new classes are appended
    """
    # ##### Collect the same information as for buildings but this time
    # for surface geometries (geometrical object) that is
    #   - collect surface geometries': id, glm-id and class
    #   - collect the names of used classes (i.e. the types of user data)
    #   - collect the hierarchical information

    # First retrieve all the concerned (geometrical) objects identifiers:
    # 3DCityDB's Building table regroups both the buildings mixed with their
    # building's sub-divisions (Building is an "abstraction" from which
    # inherits concrete building class as well building-subdivisions (parts).
    # We must first collect all the buildings and their parts:
    cursor.execute(
        "SELECT building.id "
        "FROM citydb.building JOIN citydb.cityobject ON building.id=cityobject.id "
        "                        WHERE building_root_id IN " + buildingIds)

    subBuildingIds = tuple([t[0] for t in cursor.fetchall()])

    # Then proceed with collecting the required information for those objects:
    geometricInstances = []
    cursor.execute(
        "SELECT cityobject.id, cityobject.gmlid, "
        "       thematic_surface.building_id, thematic_surface.objectclass_id, "
        "ST_AsBinary(ST_Multi(ST_Collect(surface_geometry.geometry))) "
        "FROM citydb.surface_geometry JOIN citydb.thematic_surface "
        "ON surface_geometry.root_id=thematic_surface.lod2_multi_surface_id "
        "JOIN citydb.cityobject ON thematic_surface.id=cityobject.id "
        "WHERE thematic_surface.building_id IN %s "
        "GROUP BY surface_geometry.root_id, cityobject.id, cityobject.gmlid, "
        "        thematic_surface.building_id, thematic_surface.objectclass_id",
        (subBuildingIds,))
    # In the above request we won't collect the geometry. However we still
    # retrieve it in order to disregard the instances without geometry. This
    # is because
    #   - we need the BTH data indexes to match the geometrical data indexes
    #   - when building (verb) the gltf (held in the B3dm) geometries we
    #     had to drop instances without geometrical content...
    for t in cursor.fetchall():
        if t[4] is None:
            # Some thematic surface may have no geometry (due to a cityGML
            # exporter bug?): simply ignore them.
            continue
        geometricInstances.append(
            {'internalId': t[0], 'gmlid': t[1], 'class': t[3]})
        hierarchy.addNodeToParent(t[0], t[2])
        classes.add(t[3])

    return geometricInstances


def create_batch_table_hierarchy(cursor, buildingIds):
    """
    :rtype: a TileContent in the form a B3dm.
    """

    resulting_bth = BatchTableHierarchy()

    # The constructed BatchTableHierarchy encodes the semantics of two
    # categories of objects:
    #  - non geometrical objects (building header gathering sub-buildings...)
    #  - the geometrical objects per se
    # We collect the information associated to those two categories separately:
    classes = set()
    hierarchy = TreeWithChildrenAndParent()
    buildindsAndSubParts = retrieve_buildings_and_sub_parts(cursor,
                                                            buildingIds,
                                                            classes,
                                                            hierarchy)
    geometricInstances = retrieve_geometric_instances(cursor,
                                                      buildingIds,
                                                      classes,
                                                      hierarchy)

    # ##### Retrieve the class names
    classDict = {}
    cursor.execute("SELECT id, classname FROM citydb.objectclass")
    for t in cursor.fetchall():
        # TODO: allow custom fields to be added (here + in queries)
        classDict[t[0]] = (t[1], ['gmlid'])

    # ###### All the upstream information is now retrieved from the DataBase
    # and we can proceed with the construction of the BTH

    # Within the BTH, create each required classes (as types)
    for c in classes:
        resulting_bth.add_class(classDict[c][0], classDict[c][1])

    # Build the positioning index within the constructed BatchTableHierarchy
    objectPosition = {}
    for i, (obj) in enumerate(itertools.chain(geometricInstances,
                                              buildindsAndSubParts)):
        object_id = obj['internalId']
        objectPosition[object_id] = i

    # Eventually insert objects (with geometries and without geometry)
    # associated (semantic) information. Notice that each type of object
    # (with geometries and without geometry) has its respective class
    # attributes)
    for obj in itertools.chain(geometricInstances,
                               buildindsAndSubParts):
        object_id = obj['internalId']
        resulting_bth.add_class_instance(
            classDict[obj['class']][0],
            obj,
            [objectPosition[id] for id in hierarchy.getParents(object_id)])

    return resulting_bth
