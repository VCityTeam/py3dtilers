import argparse
import numpy as np

from py3dtiles import B3dm, BatchTable, BoundingVolumeBox, GlTF, TriangleSoup
from py3dtiles import Tile, TileSet

from ..Common import kd_tree
from ..Common import create_lod_tree, create_tileset
from .citym_cityobject import CityMCityObjects
from .citym_building import CityMBuildings
from .citym_relief import CityMReliefs
from .citym_waterbody import CityMWaterBodies
from .database_accesses import open_data_base
from .database_accesses_batch_table_hierarchy import create_batch_table_hierarchy


def parse_command_line():
    # arg parse
    text = '''A small utility that build a 3DTiles tileset out of the content
               of a 3DCityDB database.'''
    parser = argparse.ArgumentParser(description=text)

    # adding positional arguments
    parser.add_argument('db_config_path',
                        nargs='?',
                        default='CityTilerDBConfig.yml',
                        type=str,  # why precise this if it is the default config ?
                        help='path to the database configuration file')

    parser.add_argument('object_type',
                        nargs='?',
                        default='building',
                        type=str,
                        choices=['building', 'relief', 'water'],
                        help='identify the object type to seek in the database')

    # adding optional arguments
    parser.add_argument('--with_BTH',
                        dest='with_BTH',
                        action='store_true',
                        help='Adds a Batch Table Hierarchy when defined')
    return parser.parse_args()

def from_3dcitydb(cursor, objects_type):
    """
    :param cursor: a database access cursor.
    :param objects_type: a class name among CityMCityObject derived classes.
                        For example, objects_type can be "CityMBuilding".

    :return: a tileset.
    """
    cityobjects = CityMCityObjects.retrieve_objects(cursor, objects_type)
    
    if not cityobjects:
        raise ValueError(f'The database does not contain any {objects_type} object')

    for cityobject in cityobjects:
        id = '(' + str(cityobject.get_database_id()) + ')'
        cursor.execute(objects_type.sql_query_geometries(id))

        for t in cursor.fetchall():
            geom_as_string = t[1]
            cityobject.geom = TriangleSoup.from_wkb_multipolygon(geom_as_string)
            cityobject.set_box()
    
    # Lump out objects in pre_tiles based on a 2D-Tree technique:
    pre_tiles = kd_tree(cityobjects, 100000)

    tree = create_lod_tree(pre_tiles, True)


    return create_tileset(tree)

def main():
    """
    :return: no return value

    this function creates a repository name "junk_object_type" where the
    tileset is stored.
    """
    args = parse_command_line()
    cursor = open_data_base(args.db_config_path)

    if args.object_type == "building":
        objects_type = CityMBuildings
        if args.with_BTH:
            CityMBuildings.set_bth()
    elif args.object_type == "relief":
        objects_type = CityMReliefs
    elif args.object_type == "water":
        objects_type = CityMWaterBodies
        
    tileset = from_3dcitydb(cursor, objects_type)

    # A shallow attempt at providing some traceability on where the resulting
    # data set comes from:
    cursor.execute('SELECT inet_client_addr()')
    server_ip = cursor.fetchone()[0]
    cursor.execute('SELECT current_database()')
    database_name = cursor.fetchone()[0]
    origin = f'This tileset is the result of Py3DTiles {__file__} script '
    origin += f'run with data extracted from database {database_name} '
    origin += f' obtained from server {server_ip}.'
    tileset.add_asset_extras(origin)

    cursor.close()
    tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
    if args.object_type == "building":
        tileset.write_to_directory('junk_buildings')
    elif args.object_type == "relief":
        tileset.write_to_directory('junk_reliefs')
    elif args.object_type == "water":
        tileset.write_to_directory('junk_water_bodies')


if __name__ == '__main__':
    main()
