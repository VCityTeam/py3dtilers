import argparse
import pathlib

from py3dtiles import BoundingVolumeBox, TriangleSoup

from ..Common import create_tileset
from ..Texture import Texture
from .citym_cityobject import CityMCityObjects, CityMCityObject
from .citym_building import CityMBuildings
from .citym_relief import CityMReliefs
from .citym_waterbody import CityMWaterBodies
from .database_accesses import open_data_base


def parse_command_line():
    # arg parse
    text = '''A small utility that build a 3DTiles tileset out of the content
               of a 3DCityDB database.'''
    parser = argparse.ArgumentParser(description=text)

    # adding positional arguments
    parser.add_argument('db_config_path',
                        nargs='?',
                        default='py3dtilers/CityTiler/CityTilerDBConfig.yml',
                        type=str,  # why precise this if it is the default config ?
                        help='path to the database configuration file')

    parser.add_argument('object_type',
                        nargs='?',
                        default='building',
                        type=str,
                        choices=['building', 'relief', 'water'],
                        help='identify the object type to seek in the database')

    parser.add_argument('--loa',
                        nargs='?',
                        type=str,
                        help='Creates a LOA when defined. The LOA is a 3D extrusion of polygons. \
                              Objects in the same polygon are merged together. \
                              Must be followed by the path to directory containing the polygons .geojson')

    # adding optional arguments
    parser.add_argument('--with_BTH',
                        dest='with_BTH',
                        action='store_true',
                        help='Adds a Batch Table Hierarchy when defined')

    parser.add_argument('--with_texture',
                        dest='with_texture',
                        action='store_true',
                        help='Adds texture to 3DTiles when defined')

    parser.add_argument('--split_surfaces',
                        dest='split_surfaces',
                        action='store_true',
                        help='Keeps the surfaces of the cityObjects split when defined')

    parser.add_argument('--lod1',
                        dest='lod1',
                        action='store_true',
                        help='Creates a LOD1 when defined. The LOD1 is a 3D extrusion of the footprint of each object.')

    result = parser.parse_args()

    return result


def get_surfaces_merged(cursor, cityobjects, objects_type):
    """
    Get the surfaces of all the cityobjects and transform them into TriangleSoup
    Surfaces of the same cityObject are merged into one geometry
    """
    cityobjects_with_geom = list()
    for cityobject in cityobjects:
        try:
            id = '(' + str(cityobject.get_database_id()) + ')'
            cursor.execute(objects_type.sql_query_geometries(id, False))
            for t in cursor.fetchall():
                geom_as_string = t[1]
                cityobject.geom = TriangleSoup.from_wkb_multipolygon(geom_as_string)
                cityobject.set_box()
                cityobjects_with_geom.append(cityobject)
        except AttributeError:
            continue
    return objects_type(cityobjects_with_geom)


def get_surfaces_split(cursor, cityobjects, objects_type):
    """
    Get the surfaces of all the cityobjects and transform them into TriangleSoup
    Surfaces of each cityObject are split into different geometries
    Each surface will be an ObjectToTile
    """
    surfaces = list()
    for cityobject in cityobjects:
        id = '(' + str(cityobject.get_database_id()) + ')'
        cursor.execute(objects_type.sql_query_geometries(id, True))
        for t in cursor.fetchall():
            surface_id = t[0]
            geom_as_string = t[1]
            if geom_as_string is not None:
                surface = CityMCityObject(surface_id)
                try:
                    surface.geom = TriangleSoup.from_wkb_multipolygon(geom_as_string)
                    surface.set_box()
                    surfaces.append(surface)
                except ValueError:
                    continue
    return CityMCityObjects(surfaces)


def get_surfaces_with_texture(cursor, cityobjects, objects_type):
    surfaces = list()
    for cityobject in cityobjects:
        id = '(' + str(cityobject.get_database_id()) + ')'
        cursor.execute(objects_type.sql_query_geometries_with_texture_coordinates(id))
        for t in cursor.fetchall():
            surface_id = t[0]
            geom_as_string = t[1]
            uv_as_string = t[2]
            texture_uri = t[3]
            if geom_as_string is not None:
                surface = CityMCityObject(surface_id)
                try:
                    associated_data = [uv_as_string]
                    surface.geom = TriangleSoup.from_wkb_multipolygon(geom_as_string, associated_data)
                    if len(surface.geom.triangles[0]) <= 0:
                        continue
                    surface.geom.triangles.append(texture_uri)
                    texture = Texture(texture_uri, objects_type, cursor, surface.geom.triangles[1])
                    surface.set_texture(texture.get_texture_image())
                    surface.set_box()
                    surfaces.append(surface)
                except ValueError:
                    continue
    return CityMCityObjects(surfaces)


def from_3dcitydb(cursor, objects_type, create_lod1=False, create_loa=False, polygons_path=None, split_surfaces=False, with_texture=False):
    """
    :param cursor: a database access cursor.
    :param objects_type: a class name among CityMCityObject derived classes.
                        For example, objects_type can be "CityMBuilding".

    :return: a tileset.
    """
    cityobjects = CityMCityObjects.retrieve_objects(cursor, objects_type)

    if not cityobjects:
        raise ValueError(f'The database does not contain any {objects_type} object')

    if with_texture:
        objects_to_tile = get_surfaces_with_texture(cursor, cityobjects, objects_type)
    else:
        if split_surfaces:
            objects_to_tile = get_surfaces_split(cursor, cityobjects, objects_type)
        else:
            objects_to_tile = get_surfaces_merged(cursor, cityobjects, objects_type)

    extension_name = None
    if CityMBuildings.is_bth_set():
        extension_name = "batch_table_hierarchy"

    return create_tileset(objects_to_tile, also_create_lod1=create_lod1, also_create_loa=create_loa, polygons_path=polygons_path, extension_name=extension_name, with_texture=with_texture)


def create_directory(directory):
    target_dir = pathlib.Path(directory).expanduser()
    pathlib.Path(target_dir).mkdir(parents=True, exist_ok=True)
    target_dir = pathlib.Path(directory + '/tiles').expanduser()
    pathlib.Path(target_dir).mkdir(parents=True, exist_ok=True)
    Texture.set_texture_folder(directory)


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
        create_directory('junk_buildings')
        if args.with_BTH:
            CityMBuildings.set_bth()
    elif args.object_type == "relief":
        create_directory('junk_reliefs')
        objects_type = CityMReliefs
    elif args.object_type == "water":
        objects_type = CityMWaterBodies

    create_loa = args.loa is not None

    objects_type.set_cursor(cursor)

    split_surfaces = args.split_surfaces or args.with_texture

    tileset = from_3dcitydb(cursor, objects_type, args.lod1, create_loa, args.loa, split_surfaces, args.with_texture)

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
