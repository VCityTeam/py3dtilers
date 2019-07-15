"""
Notes on the 3DCityDB database general structure

The data is organised in the following way in the database:

### for buildings
  - the building table contains the "abstract" building
    subdivisions (building, building part)
  - the thematic_surface table contains all the surface objects (wall,
    roof, floor), with links to the building object it belongs to
    and the geometric data in the surface_geometry table
  - the surface_geometry table contains the geometry of the surface
    (and volumic too for some reason) objects
  - the cityobject table contains both the thematic_surface and
    the building objects

### for reliefs
  - the relief_feature table contains the complex relief objects which are composed
    by individual components that can be of different types - TIN/raster etc.)
  - the relief_component table contains individual relief components
  - the relief_feat_to_rel_comp table establishes a link between individual components and
    their "parent" which is a more complex relief object
"""


import sys
import yaml
import psycopg2
import psycopg2.extras

from py3dtiles import TriangleSoup
from cityobject import CityObject, CityObjects


def open_data_base(db_config_file_path):
    with open(db_config_file_path, 'r') as db_config_file:
        try:
            db_config = yaml.load(db_config_file, Loader=yaml.FullLoader)
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


def open_data_bases(db_config_file_paths):
    cursors = list()
    for file_path in db_config_file_paths:
        cursors.append(open_data_base(file_path))
    return cursors


def get_buildings_from_3dcitydb(cursor, buildings=None):
    """
    :param cursor: a database access cursor
    :param buildings: an optional list of objects with a get_gmlid() method
                      (that returns the (city)gml identifier of a building
                      object that should be encountered in the database) that
                      should be seeked in the database. When this list is
                      is empty all the buildings encountered in the database
                      are returned.
    :return: the list of the buildings that were retrieved in the 3DCityDB
             database, each building being decorated with its database
             identifier as well as its 3D bounding box (as retrieved in the.
             database)
    """
    if not buildings:
        no_input_buildings = True
        # No specific building were seeked. We thus retrieve all the ones
        # we can find in the database:
        query = "SELECT building.id, BOX3D(cityobject.envelope) " + \
                "FROM building JOIN cityobject ON building.id=cityobject.id "+\
                "WHERE building.id=building.building_root_id"
    else:
        no_input_buildings = False
        building_gmlids = [n.get_gml_id() for n in buildings]
        building_gmlids_as_string = "('" + "', '".join(building_gmlids) + "')"
        query = "SELECT building.id, BOX3D(cityobject.envelope), cityobject.gmlid " + \
                "FROM building JOIN cityobject ON building.id=cityobject.id "+\
                "WHERE cityobject.gmlid IN " + building_gmlids_as_string + " "\
                "AND building.id=building.building_root_id"
    cursor.execute(query)

    if no_input_buildings:
        result_buildings = CityObjects()
    else:
        # We need to deal with the fact that the answer will (generically)
        # not preserve the order of the objects that was given to the query
        buildings_with_gmlid_key = dict()
        for building in buildings:
            buildings_with_gmlid_key[building.gml_id] = building

    for t in cursor.fetchall():
        building_id = t[0]
        if not t[1]:
            print("Warning: building with id ", building_id)
            print("         has no 'cityobject.envelope'.")
            if no_input_buildings:
                print("     Dropping this building (downstream trouble ?)")
                continue
            print("     Exiting (is the database corrupted ?)")
            sys.exit(1)
        box = t[1]
        if no_input_buildings:
            new_building = CityObject(building_id, box)
            result_buildings.append(new_building)
        else:
            gml_id = t[2]
            building = buildings_with_gmlid_key[gml_id]
            building.set_database_id(building_id)
            building.set_box(box)
    if no_input_buildings:
        return result_buildings
    else:
        return buildings


def get_reliefs_from_3dcitydb(cursor, reliefs=None):
    """
    :param cursor: a database access cursor
    :param reliefs: an optional list of objects with a get_gmlid() method
                      (that returns the (city)gml identifier of a relief
                      object that should be encountered in the database) that
                      should be seeked in the database. When this list is
                      is empty all the reliefs encountered in the database
                      are returned.

    :return: the list of the reliefs that were retrieved in the 3DCityDB
             database, each relief being decorated with its database
             identifier as well as its 3D bounding box (as retrieved in the.
             database)
    """
    if not reliefs:
        no_input_reliefs = True
        # No specific building were seeked. We thus retrieve all the ones
        # we can find in the database:
        query = "SELECT relief_feature.id, BOX3D(cityobject.envelope) " + \
                "FROM relief_feature JOIN cityobject ON relief_feature.id=cityobject.id"

    else:
        no_input_reliefs = False
        relief_gmlids = [n.get_gml_id() for n in reliefs]
        relief_gmlids_as_string = "('" + "', '".join(relief_gmlids) + "')"
        query = "SELECT relief_feature.id, BOX3D(cityobject.envelope) " + \
                "FROM relief_feature JOIN cityobject ON relief_feature.id=cityobject.id" + \
                "WHERE cityobject.gmlid IN " + relief_gmlids_as_string

    cursor.execute(query)


def retrieve_geometries(cursor, buildingIds, offset):
    """
    :param cursor: a database access cursor
    :param buildings: an list of (city)gml identifier corresponding to
                      building objects.
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

    building_ids_arg = str(buildingIds).replace(',)',')')

    query = \
        "SELECT building.building_root_id, ST_AsBinary(ST_Multi(ST_Collect( " +\
        "ST_Translate(surface_geometry.geometry, " + \
        str(-offset[0]) + ", " + str(-offset[1]) + ", " + str(-offset[2]) + \
        ")))) " + \
        "FROM surface_geometry JOIN thematic_surface " + \
        "ON surface_geometry.root_id=thematic_surface.lod2_multi_surface_id " + \
        "JOIN building ON thematic_surface.building_id = building.id " + \
        "WHERE building.building_root_id IN " + building_ids_arg + " " +\
        "GROUP BY building.building_root_id "
    cursor.execute(query)

    # Deal with the reordering of the retrieved geometries
    buildings_with_gmlid_key = dict()
    for t in cursor.fetchall():
        building_root_id = t[0]
        geom_as_string = t[1]
        if geom_as_string is None:
            # Some thematic surface may have no geometry (due to a cityGML
            # exporter bug?): simply ignore them.
            print("Warning: no valid geometry in database.")
            sys.exit(1)
        geom = TriangleSoup.from_wkb_multipolygon(geom_as_string)
        if len(geom.triangles[0]) == 0:
            print("Warning: empty geometry (no geometry) from the database.")
            sys.exit(1)
        buildings_with_gmlid_key[building_root_id] = geom

    # Package the geometries within a data structure that the
    # GlTF.from_binary_arrays() function (see below) expects to consume:
    arrays = []
    for incoming_id in buildingIds:
        geom = buildings_with_gmlid_key[incoming_id]
        arrays.append({
            'position': geom.getPositionArray(),
            'normal': geom.getNormalArray(),
            'bbox': [[float(i) for i in j] for j in geom.getBbox()]
        })

    return arrays