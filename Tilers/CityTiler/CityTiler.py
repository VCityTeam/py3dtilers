import sys
import argparse
import yaml
import numpy as np
import itertools
import psycopg2
import psycopg2.extras

from py3dtiles import B3dm, BatchTableHierarchy, BoundingVolumeBox, GlTF
from py3dtiles import Tile, TileSet, TriangleSoup


def ParseCommandLine():
    # arg parse
    descr = '''A small utility that build a 3DTiles tileset out of the content
               of a 3DCityDB database.'''
    parser = argparse.ArgumentParser(description=descr)
    parser.add_argument('db_config_path',
                        nargs='?',
                        default='CityTilerDBConfig.yml',
                        type=str,
                        help='Path to the database configuration file')
    parser.add_argument('--with_BT',
                        dest='with_BT',
                        action='store_true',
                        help='Adds a Batch Table when defined')
    parser.add_argument('--with_BTH',
                        dest='with_BTH',
                        action='store_true',
                        help='Adds a Batch Table Hierachy when defined')
    return parser.parse_args()


def OpenDataBase(args):

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


class Building(object):

    def __init__(self, id, box_in):
        """
        :param id: given identifier
        :param box_2D: the maximum extents of the geometry a returned by a
                       PostGis::Box3D(geometry geomA) call (refer to
                       https://postgis.net/docs/Box3D.html) that is a string
                       of the form 'BOX3D(1 2 3, 4 5 6)' where:
                        * 1, 2 and 3 are the respective minimum of X, Y and Z
                        * 4, 5 and 6 are the respective maximum of X, Y and Z
        """
        self.id = id
        # 'BOX3D(1 2 3, 4 5 6)' -> [[1, 2, 3], [4, 5, 6]]
        box_parsed = [[float(coord) for coord in point.split(' ')]
                                    for point in box_in[6:-1].split(',')]
        x_min = box_parsed[0][0]
        x_max = box_parsed[1][0]
        y_min = box_parsed[0][1]
        y_max = box_parsed[1][1]
        z_min = box_parsed[0][2]
        z_max = box_parsed[1][2]

        self.box = BoundingVolumeBox()
        self.box.set_from_mins_maxs([x_min, y_min, z_min, x_max, y_max, z_max])
        # Centroid of the box
        self.centroid = [(x_min + x_max) / 2.0,
                         (y_min + y_max) / 2.0,
                         (z_min + z_max) / 2.0]

    def getId(self):
        return self.id

    def getCentroid(self):
        return self.centroid

    def getBoundingVolumeBox(self):
        return self.box


class Buildings:
    """
    A decorated list of Buildings.
    """
    def __init__(self, buildings=None):
        self.buildings = list()
        if buildings:
            self.buildings.extend(buildings)

    def __iter__(self):
        return iter(self.buildings)

    def __getitem__(self, item):
        return Buildings(self.buildings.__getitem__(item))

    def append(self, building):
        self.buildings.append(building)

    def extend(self, others):
        self.buildings.extend(others)

    def __len__(self):
        return len(self.buildings)

    def getCentroid(self):
        centroid = [0., 0., 0.]
        for building in self:
            centroid[0] += building.getCentroid()[0]
            centroid[1] += building.getCentroid()[1]
            centroid[2] += building.getCentroid()[2]
        return [centroid[0] / len(self),
                centroid[1] / len(self),
                centroid[2] / len(self)]


def kd_tree(buildings, maxNumBuildings, depth=0):
    # The module argument of 2 (in the next line) hard-wires the fact that
    # this kd_tree is in fact a 2D_tree.
    axis = depth % 2

    # Within the sorting criteria point[1] refers to the centroid of the
    # bounding boxes of the buildings. And thus, depending on the value of
    # axis, we alternatively sort on the X or Y coordinate of those centroids:
    sBuildings = Buildings(
                    sorted(buildings,
                    key=lambda building: building.getCentroid()[axis]))
    median = len(sBuildings) // 2
    lBuildings = sBuildings[:median]
    rBuildings = sBuildings[median:]
    pre_tiles = Buildings()
    if len(lBuildings) > maxNumBuildings:
        pre_tiles.extend(kd_tree(lBuildings, maxNumBuildings, depth + 1))
        pre_tiles.extend(kd_tree(rBuildings, maxNumBuildings, depth + 1))
    else:
        pre_tiles.append(lBuildings)
        pre_tiles.append(rBuildings)
    return pre_tiles


def create_tile_content(cursor, buildingIds, offset, args):
    """
    :param offset: the offset (a a 3D "vector" of floats) by which the
                   geographical coordinates should be translated (the
                   computation is done at the GIS level)
    :type args: CLI arguments as obtained with an ArgumentParser. Used to
                determine whether to define attach an optional
                BatchTable or possibly a BatchTableHierachy
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

    # GlTF uses a y-up coordinate system whereas the geographical data (stored
    # in the 3DCityDB database) uses a z-up coordinate system convention. In
    # order to comply with Gltf we thus need to realize a z-up to y-up
    # coordinate transform for the data to respect the glTF convention. This
    # rotation gets "corrected" (taken care of) by the B3dm/gltf parser on the
    # client side when using (displaying) the data.
    # Refer to the note concerning the recommended data workflow
    #    https://github.com/AnalyticalGraphicsInc/3d-tiles/tree/master/specification#gltf-transforms
    # for more details on this matter.
    transform = np.array([1, 0,  0, 0,
                          0, 0, -1, 0,
                          0, 1,  0, 0,
                          0, 0,  0, 1])
    gltf = GlTF.from_binary_arrays(arrays, transform)

    bth = create_batch_table_hierachy(cursor, buildingIds, args)

    # Eventually wrap the geometries together with the BatchTableHierarchy
    # within a B3dm:
    return B3dm.from_glTF(gltf, bth)

def create_batch_table_hierachy(cursor, buildingIds, args):
    """
    :type args: CLI arguments as obtained with an ArgumentParser. Used to
                determine whether to define attach an optional
                BatchTable or possibly a BatchTableHierachy
    :rtype: a TileContent in the form a B3dm.
    """

    class TreeWithChildrenAndParent:
        """
        A simple hierarchy/Direct Acyclic Graph, as in
        https://en.wikipedia.org/wiki/Tree_%28data_structure%29) with both
        children and parent relationships explicitly represented (for the
        sake of retrieval efficiency) as dictionaries using some user
        defined identifier as keys. TreeWithChildrenAndParent is not
        responsible of the identifiers and simply uses them as provided
        weak references.
        """

        def __init__(self):
            """Children of a given id (given as dict key)"""
            self.hierarchy = {}
            """Parents of a given id (given as dict key)"""
            self.reverseHierarchy = {}

        def addNodeToParent(self, object_id, parent_id):
            if parent_id is not None:
                if parent_id not in self.hierarchy:
                    self.hierarchy[parent_id] = []
                self.hierarchy[parent_id].append(object_id)
                self.reverseHierarchy[object_id] = parent_id

        def getParents(self, object_id):
            if object_id in self.reverseHierarchy:
                return [self.reverseHierarchy[object_id]]
            return []

    resulting_bth = BatchTableHierarchy()

    # The constructed BatchTableHierarchy encodes the semantics of two
    # categories of objects:
    #  - the geometrical objects but also,
    #  - non geometrical objects (building header gathering sub-buildings...)
    # We collect the information associated to those two categories separately:

    # ##### Walk on the building and
    #   - collect buildings': id, glm-id and class
    #   - collect the names of used classes (i.e. the types of user data)
    #   - collect the hierarchical information
    buildindsAndSubParts = []
    classes = set()
    hierarchy = TreeWithChildrenAndParent()
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

    # ##### Retrieve the class names of the encountered classes
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


def from_3dcitydb(cursor, args):
    """
    :type args: CLI arguments as obtained with an ArgumentParser.
    """

    # Retrieve all the buildings encountered in the 3DCityDB database together
    # with their 3D bounding box.
    cursor.execute("SELECT building.id, BOX3D(cityobject.envelope) "
        "FROM building JOIN cityobject ON building.id=cityobject.id "
        "WHERE building.id=building.building_root_id")
    buildings = Buildings()
    for t in cursor.fetchall():
        id = t[0]
        box = t[1]
        buildings.append(Building(id, box))

    # Lump out buildings in pre_tiles based on a 2D-Tree technique:
    pre_tiles = kd_tree(buildings, 20)

    tileset = TileSet()
    for tile_buildings in pre_tiles:
        tile = Tile()
        tile.set_geometric_error(500)

        # Construct the tile content and attach it to the new Tile:
        ids = tuple([building.getId() for building in tile_buildings])
        centroid = tile_buildings.getCentroid()
        tile_content_b3dm = create_tile_content(cursor, ids, centroid, args)
        tile.set_content(tile_content_b3dm)

        # The current new tile bounding volume shall be a box enclosing the
        # buildings withheld in the considered tile_buildings:
        bounding_box = BoundingVolumeBox()
        for building in tile_buildings:
            bounding_box.add(building.getBoundingVolumeBox())

        # The Tile Content returned by the above call to create_tile_content()
        # (refer to the usage of the centroid/offset third argument) uses
        # coordinates that are local to the centroid (considered as a
        # referential system within the chosen geographical coordinate system).
        # Yet the above computed bounding_box was set up based on
        # coordinates that are relative to the chosen geographical coordinate
        # system. We thus need to align the Tile Content to the
        # BoundingVolumeBox of the Tile by "adjusting" to this change of
        # referential:
        bounding_box.translate([- centroid[i] for i in range(0,3)])
        tile.set_bounding_volume(bounding_box)

        # The transformation matrix for the tile is limited to a translation
        # to the centroid (refer to the offset realized by the
        # create_tile_content() method).
        # Note: the geographical data (stored in the 3DCityDB) uses a z-up
        #       referential convention. When building the B3dm/gltf, and in
        #       order to comply to the y-up gltf convention) it was necessary
        #       (look for the definition of the `transform` matrix when invoking
        #       `GlTF.from_binary_arrays(arrays, transform)` in the
        #        create_tile_content() method) to realize a z-up to y-up
        #        coordinate transform. The Tile is not aware on this z-to-y
        #        rotation (when writing the data) followed by the invert y-to-z
        #        rotation (when reading the data) that only concerns the gltf
        #        part of the TileContent.
        tile.set_transform([1, 0, 0, 0,
                            0, 1, 0, 0,
                            0, 0, 1, 0,
                           centroid[0], centroid[1], centroid[2], 1])

        # Eventually we can add the newly build tile to the tile set:
        tileset.add_tile(tile)

    # Note: we don't need to explicitly adapt the TileSet's root tile
    # bounding volume, because TileSet::write_to_directory() already
    # takes care of this synchronisation.

    # A shallow attempt at providing some traceability on where the resulting
    # data set comes from:
    cursor.execute('SELECT inet_client_addr()')
    server_ip = cursor.fetchone()[0]
    cursor.execute('SELECT current_database()')
    database_name = cursor.fetchone()[0]
    origin  = f'This tileset is the result of Py3DTiles {__file__} script '
    origin += f'run with data extracted from database {database_name} '
    origin += f' obtained from server {server_ip}.'
    tileset.add_asset_extras(origin)

    return tileset


if __name__ == '__main__':
    args = ParseCommandLine()
    cursor = OpenDataBase(args)
    tileset = from_3dcitydb(cursor, args)
    cursor.close()
    tileset.write_to_directory('junk')
