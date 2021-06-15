import os
import argparse
import sys

from py3dtiles import BoundingVolumeBox
from .geojson import Geojsons
from ..Common import create_lod_tree, create_tileset


def parse_command_line():
    # arg parse
    text = '''A small utility that build a 3DTiles tileset out of the content
               of an geojson repository'''
    parser = argparse.ArgumentParser(description=text)

    # adding positional arguments
    parser.add_argument('--paths',
                        nargs='*',
                        type=str,
                        help='path to the database configuration file')

    parser.add_argument('--group',
                        nargs='*',
                        type=str,
                        help='method to merge features together')

    parser.add_argument('--properties',
                        nargs='*',
                        type=str,
                        help='name of the properties to read in Geojson files')

    parser.add_argument('--obj',
                        nargs='*',
                        type=str,
                        help='create also obj model with specified name')

    result = parser.parse_args()

    if(result.group is None):
        result.group = ['none']

    if(result.obj is None):
        result.obj = ['']
    elif(len(result.obj) == 0):
        result.obj = ['result.obj']
    elif('.obj' not in result.obj[0]):
        result.obj[0] = result.obj[0] + '.obj'

    if(result.properties is None or len(result.properties) % 2 != 0):
        result.properties = ['height', 'HAUTEUR', 'z', 'Z_MAX', 'prec', 'PREC_ALTI']
    else:
        if('height' not in result.properties):
            result.properties += ['height', 'HAUTEUR']
        if('prec' not in result.properties):
            result.properties += ['prec', 'PREC_ALTI']
        if('z' not in result.properties):
            result.properties += ['z', 'Z_MAX']

    if(result.paths is None):
        print("Please provide a path to a directory "
              "containing some geojson files")
        print("Exiting")
        sys.exit(1)

    return result


def from_geojson_directory(path, group, properties, obj_name):
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

    tree = create_lod_tree([objects], False)

    if len(Geojsons.base_features) > 0:
        for index, node in enumerate(tree.root_nodes):
            features = [Geojsons.base_features[i] for i in Geojsons.features_dict[index]]
            node.set_child_nodes(features)

    return create_tileset(tree)


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
    path = args.paths[0]
    obj_name = args.obj[0]
    if(os.path.isdir(path)):
        print("Writing " + path)
        tileset = from_geojson_directory(path, args.group, args.properties, obj_name)
        if(tileset is not None):
            tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
            folder_name = path.split('/')[-1]
            print("tileset in geojson_tilesets/" + folder_name)
            tileset.write_to_directory("geojson_tilesets/" + folder_name)


if __name__ == '__main__':
    main()
