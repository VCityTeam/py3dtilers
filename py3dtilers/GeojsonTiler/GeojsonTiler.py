import os
import argparse
import sys

from py3dtiles import BoundingVolumeBox
from .geojson import Geojsons
from ..Common import create_tileset


def parse_command_line():
    # arg parse
    text = '''A small utility that build a 3DTiles tileset out of the content
               of an geojson repository'''
    parser = argparse.ArgumentParser(description=text)

    # adding positional arguments
    parser.add_argument('--path',
                        nargs=1,
                        help='Path to the directory containing .geojson files')

    parser.add_argument('--group',
                        nargs='*',
                        type=str,
                        help='Method to merge features together.\
                              The available choices are cube, road and polygon.\
                              The cube option can be followed by the size of cubes (as int).')

    parser.add_argument('--obj',
                        nargs='?',
                        type=str,
                        help='When defined, also create an .obj model of the features.\
                             The flag must be followed by the name of the obj that will be created.')

    parser.add_argument('--loa',
                        nargs='?',
                        type=str,
                        help='Creates a LOA when defined. The LOA is a 3D extrusion of polygons.\
                              Objects in the same polygon are merged together.\
                              Must be followed by the path to directory containing the polygons .geojson')

    parser.add_argument('--lod1',
                        dest='lod1',
                        action='store_true',
                        help='Creates a LOD1 when defined. The LOD1 is a 3D extrusion of the footprint of each object.')

    parser.add_argument('--height',
                        nargs='?',
                        default='HAUTEUR',
                        type=str,
                        help='Change the name of the propertie to look for in the feature for height.\
                              Default property name is HAUTEUR')

    parser.add_argument('--prec',
                        nargs='?',
                        default='PREC_ALTI',
                        type=str,
                        help='Change the name of the propertie to look for in the feature for altitude precision.\
                              Default property name is PREC_ALTI')

    result = parser.parse_args()

    if(result.group is None):
        result.group = ['none']

    if(result.obj is not None and '.obj' not in result.obj):
        result.obj = result.obj + '.obj'

    if(result.path is None):
        print("Please provide a path to a directory "
              "containing some geojson files")
        print("Exiting")
        sys.exit(1)

    return result


def from_geojson_directory(path, group, properties, obj_name=None, create_lod1=False, create_loa=False, loa_path=None):
    """
    :param path: a path to a directory

    :return: a tileset.
    """

    objects = Geojsons.retrieve_geojsons(path, group, properties, obj_name)

    if(len(objects) == 0):
        print("No .geojson found in " + path)
        return None
    else:
        print(str(len(objects)) + " features parsed")

    return create_tileset(objects, also_create_lod1=create_lod1, also_create_loa=create_loa, loa_path=loa_path)


def main():
    """
    :return: no return value

    this function creates either :
    - a repository named "geojson_tileset" where the
    tileset is stored if the directory does only contains geojson files.
    - or a repository named "geojson_tilesets" that contains all tilesets are stored
    created from sub_directories
    and a classes.txt that contains the name of all tilesets
    """
    args = parse_command_line()
    path = args.path[0]

    create_lod1 = args.lod1
    create_loa = args.loa is not None

    properties = ['height', args.height, 'prec', args.prec]

    if(os.path.isdir(path)):
        print("Writing " + path)
        tileset = from_geojson_directory(path, args.group, properties, args.obj, create_lod1, create_loa, args.loa)
        if(tileset is not None):
            tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
            folder_name = path.split('/')[-1]
            print("tileset in geojson_tilesets/" + folder_name)
            tileset.write_to_directory("geojson_tilesets/" + folder_name)


if __name__ == '__main__':
    main()
