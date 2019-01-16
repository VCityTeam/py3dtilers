import sys
import yaml
import itertools
import psycopg2
import psycopg2.extras

from py3dtiles import BatchTableHierarchy
from py3dtiles import TriangleSoup

from tree_with_children_and_parent import TreeWithChildrenAndParent


# ##### Notes on the 3DCityDB database general structure

# The data is organised in the following way in the database:
#   - the building table contains the "abstract" building
#     subdivisions (building, building part)
#   - the thematic_surface table contains all the surface objects (wall,
#     roof, floor), with links to the building object it belongs to
#     and the geometric data in the surface_geometry table
#   - the surface_geometry table contains the geometry of the surface
#     (and volumic too for some reason) objects
#   - the cityobject table contains both the thematic_surface and
#     the building objects

def open_data_base(args):
    with open(args.db_config_path, 'r') as db_config_file:
        try:
            db_config = yaml.load(db_config_file)
            db_config_file.close()
        except:
            print('ERROR: ', sys.exec_info()[0])
            db_config_file.close()
            sys.exit()

    # Check that db configuration is well defined
    if (   ("PG_HOST" not in db_config)
        or ("PG_USER" not in db_config)
        or ("PG_NAME" not in db_config)
        or ("PG_PORT" not in db_config)
        or ("PG_PASSWORD" not in db_config)):
        print(("ERROR: Database is not properly defined in '{0}', please refer to README.md"
              .format(args.db_config_path)))
        sys.exit()

    # Connect to database
    db = psycopg2.connect(
        "postgresql://{0}:{1}@{2}:{3}/{4}"
        .format(db_config['PG_USER'],
                db_config['PG_PASSWORD'],
                db_config['PG_HOST'],
                db_config['PG_PORT'],
                db_config['PG_NAME']),
        # fetch method will return named tuples instead of regular tuples
        cursor_factory=psycopg2.extras.NamedTupleCursor,
    )

    try:
        # Open a cursor to perform database operations
        cursor = db.cursor()
        cursor.execute('SELECT 1')
    except psycopg2.OperationalError:
        print('ERROR: unable to connect to database')
        sys.exit()

    return cursor


def retrieve_geometries(cursor, buildingIds, offset):
    """
    :param offset: the offset (a a 3D "vector" of floats) by which the
                   geographical coordinates should be translated (the
                   computation is done at the GIS level)
    :rtype: a TileContent in the form a B3dm.
    """

    # ##### Collect the necessary information from a 3DCityDB database:

    # The data is organised in the following way in the database:
    #   - the building table contains the "abstract" building
    #     subdivisions (building, building part)
    #   - the thematic_surface table contains all the surface objects (wall,
    #     roof, floor), with links to the building object it belongs to
    #     and the geometric data in the surface_geometry table
    #   - the surface_geometry table contains the geometry of the surface
    #     (and volumic too for some reason) objects
    #   - the cityobject table contains both the thematic_surface and
    #     the building objects

    # Because the 3DCityDB's Building table regroups both the buildings mixed
    # with their building's sub-divisions (Building is an "abstraction"
    # from which inherits concrete building class as well building-subdivisions
    # a.k.a. parts) we must first collect all the buildings and their parts:
    cursor.execute(
        "SELECT building.id "
        "FROM building JOIN cityobject ON building.id=cityobject.id "
        "                        WHERE building_root_id IN %s", (buildingIds,))

    subBuildingIds = tuple([t[0] for t in cursor.fetchall()])

    # Collect the (so called) surface geometries:
    cursor.execute(
        "SELECT ST_AsBinary(ST_Multi(ST_Collect("
        "            ST_Translate(surface_geometry.geometry, -%s, -%s, -%s)))) "
        "FROM surface_geometry JOIN thematic_surface "
        "ON surface_geometry.root_id=thematic_surface.lod2_multi_surface_id "
        "JOIN cityobject ON thematic_surface.id=cityobject.id "
        "WHERE thematic_surface.building_id IN %s "
        "GROUP BY surface_geometry.root_id, cityobject.id, cityobject.gmlid, "
        "        thematic_surface.building_id, thematic_surface.objectclass_id",
        (offset[0], offset[1], offset[2], subBuildingIds,))

    # Package the geometries within a data structure that the
    # GlTF.from_binary_arrays() function (see below) expects to consume:
    arrays = []
    for t in cursor.fetchall():
        if t[0] is None:
            # Some thematic surface may have no geometry (due to a cityGML
            # exporter bug?): simply ignore them.
            continue
        geom = TriangleSoup.from_wkb_multipolygon(t[0])
        # Objects without triangulated geometries are simply dropped out:
        if len(geom.triangles[0]) != 0:
            arrays.append({
                'position': geom.getPositionArray(),
                'normal': geom.getNormalArray(),
                'bbox': [[float(i) for i in j] for j in geom.getBbox()]
            })

    return arrays


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
        "FROM building JOIN cityobject ON building.id=cityobject.id "
        "                        WHERE building_root_id IN %s", (buildingIds,))
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
        "FROM building JOIN cityobject ON building.id=cityobject.id "
        "                        WHERE building_root_id IN %s", (buildingIds,))

    subBuildingIds = tuple([t[0] for t in cursor.fetchall()])

    # Then proceed with collecting the required information for those objects:
    geometricInstances = []
    cursor.execute(
        "SELECT cityobject.id, cityobject.gmlid, "
        "       thematic_surface.building_id, thematic_surface.objectclass_id, "
        "ST_AsBinary(ST_Multi(ST_Collect(surface_geometry.geometry))) "
        "FROM surface_geometry JOIN thematic_surface "
        "ON surface_geometry.root_id=thematic_surface.lod2_multi_surface_id "
        "JOIN cityobject ON thematic_surface.id=cityobject.id "
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

def create_batch_table_hierachy(cursor, buildingIds, args):
    """
    :type args: CLI arguments as obtained with an ArgumentParser. Used to
                determine whether to define attach an optional
                BatchTable or possibly a BatchTableHierachy
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
    cursor.execute("SELECT id, classname FROM objectclass")
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