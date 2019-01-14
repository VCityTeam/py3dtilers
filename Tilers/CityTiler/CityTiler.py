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
    descr = '''TODO.'''
    parser = argparse.ArgumentParser(description=descr)
    cfg_help = 'Path to the database configuration file'
    parser.add_argument('db_config_path',
                        nargs='?', default='CityTilerDBConfig.yml',
                        type=str, help=cfg_help)
    args = parser.parse_args()

    db_config = None
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

    return db_config


def OpenDataBase(configuration):
    # Connect to database
    db = psycopg2.connect(
        "postgresql://{0}:{1}@{2}:{3}/{4}"
        .format(configuration['PG_USER'],
                configuration['PG_PASSWORD'],
                configuration['PG_HOST'],
                configuration['PG_PORT'],
                configuration['PG_NAME']),
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


def from_3dcitydb(cursor):
    # Get all buildings
    cursor.execute('SELECT building.id, BOX3D(cityobject.envelope) FROM building JOIN cityobject ON building.id=cityobject.id WHERE building.id=building.building_root_id')
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
        tile_content_b3dm = create_tile_content(cursor, ids, centroid)
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
    # "automagically" takes care of it.

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


def create_tile_content(cursor, buildingIds, offset):

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

    # ##### Collect the necessary information from a 3DCityDB database:
    objects = []
    classes = set()
    hierarchy = TreeWithChildrenAndParent()

    # Get building objects' id, class and hierarchy
    cursor.execute("SELECT building.id, building_parent_id, cityobject.gmlid, cityobject.objectclass_id FROM building JOIN cityobject ON building.id=cityobject.id WHERE building_root_id IN %s", (buildingIds,))
    for t in cursor.fetchall():
        objects.append({'internalId': t[0], 'gmlid': t[2], 'class': t[3]})
        hierarchy.addNodeToParent(t[0], t[1])
        classes.add(t[3])

    # Building + descendants ids
    subBuildingIds = tuple([i['internalId'] for i in objects])

    # Get surface geometries' id and class
    cursor.execute("SELECT cityobject.id, cityobject.gmlid, thematic_surface.building_id, thematic_surface.objectclass_id, ST_AsBinary(ST_Multi(ST_Collect(ST_Translate(surface_geometry.geometry, -%s, -%s, -%s)))) FROM surface_geometry JOIN thematic_surface ON surface_geometry.root_id=thematic_surface.lod2_multi_surface_id JOIN cityobject ON thematic_surface.id=cityobject.id WHERE thematic_surface.building_id IN %s GROUP BY surface_geometry.root_id, cityobject.id, cityobject.gmlid, thematic_surface.building_id, thematic_surface.objectclass_id", (offset[0], offset[1], offset[2], subBuildingIds,))
    for t in cursor.fetchall():
        if t[4] is None:
            # Some thematic surface may have no geometry (cityGML exporter bug?): ignore them
            continue
        objects.append({'internalId': t[0], 'gmlid': t[1], 'class': t[3], 'geometry': t[4]})
        hierarchy.addNodeToParent(t[0], t[2])
        classes.add(t[3])

    geometricInstances = [(o['internalId'], o) for o in objects if 'geometry' in o]

    # ##### Proceed with encoding the geometries within a gltf (objects without
    # geometries are thus simply dropped out):
    arrays = []
    for object_id, obj in geometricInstances:
        geom = TriangleSoup.from_wkb_multipolygon(obj['geometry'])
        if len(geom.triangles[0]) != 0:
            arrays.append({
                'position': geom.getPositionArray(),
                'normal': geom.getNormalArray(),
                'bbox': [[float(i) for i in j] for j in geom.getBbox()]
            })
        else:
            # Weed out those objects that are deprived from a real geometry,
            # in order for further treatments not having to deal with them
            del geometricInstances[object_id]

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

    # ##### Proceed with the creation of a BathTableHierarchy:
    bth = BatchTableHierarchy()

    # Get class names
    classDict = {}
    cursor.execute("SELECT id, classname FROM objectclass")
    for t in cursor.fetchall():
        # TODO: allow custom fields to be added (here + in queries)
        classDict[t[0]] = (t[1], ['gmlid'])

    # Create each respective class
    for c in classes:
        bth.add_class(classDict[c][0], classDict[c][1])

    # The constructed BatchTableHierarchy encodes the semantics of the
    # geometrical objects but also of non geometrical objects:
    nonGeometricInstances = [(o['internalId'], o)
                             for o in objects if 'geometry' not in o]

    # Positioning index in the constructed BatchTableHierarchy
    objectPosition = {}
    for i, (object_id, _) in enumerate(itertools.chain(geometricInstances,
                                                       nonGeometricInstances)):
        objectPosition[object_id] = i

    # First insert objects with geometries and then objects without geometry
    # (each object having its respective class attributes)
    for object_id, obj in itertools.chain(geometricInstances,
                                          nonGeometricInstances):
        bth.add_class_instance(
            classDict[obj['class']][0],
            obj,
            [objectPosition[id] for id in hierarchy.getParents(object_id)])

    # Eventually wrap the geometries together with the BatchTableHierarchy
    # within a B3dm:
    return B3dm.from_glTF(gltf, bth)


if __name__ == '__main__':
    cursor = OpenDataBase(ParseCommandLine())
    tileset = from_3dcitydb(cursor)
    cursor.close()
    tileset.write_to_directory('junk')
