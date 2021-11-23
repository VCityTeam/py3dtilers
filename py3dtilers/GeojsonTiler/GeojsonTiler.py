import os
import argparse
import sys
from os import listdir
import json

from pathlib import Path
from py3dtiles import BoundingVolumeBox
from .geojson import Geojsons
from .geojson_line import GeojsonLine
from .geojson_polygon import GeojsonPolygon
from ..Common import create_tileset


def parse_command_line():
    # arg parse
    text = '''A small utility that build a 3DTiles tileset out of the content
               of an geojson repository'''
    parser = argparse.ArgumentParser(description=text)

    # adding positional arguments
    parser.add_argument('--path',
                        nargs=1,
                        type=str,
                        help='Path to the directory containing .geojson files')

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
                              The value can be a float, this will set the default height.\
                              Default property name is HAUTEUR')

    parser.add_argument('--width',
                        nargs='?',
                        default='LARGEUR',
                        type=str,
                        help='Change the name of the propertie to look for in the feature for width.\
                              The value can be a float, this will set the default width.\
                              Default property name is LARGEUR')

    parser.add_argument('--prec',
                        nargs='?',
                        default='PREC_ALTI',
                        type=str,
                        help='Change the name of the propertie to look for in the feature for altitude precision.\
                              Default property name is PREC_ALTI')

    parser.add_argument('--is_roof',
                        dest='is_roof',
                        action='store_true',
                        help='When defined, the features from geojsons will be considered as rooftops.\
                              We will thus substract the height from the coordinates to reach the floor.')

    result = parser.parse_args()

    if(result.obj is not None and '.obj' not in result.obj):
        result.obj = result.obj + '.obj'

    if(result.path is None):
        print("Please provide a path to a directory "
              "containing some geojson files")
        print("Exiting")
        sys.exit(1)

    return result


def get_geojson_instance(id, feature_geometry, feature_properties):
    return {
        'Polygon': GeojsonPolygon(id, feature_properties, feature_geometry),
        'MultiPolygon': GeojsonPolygon(id, feature_properties, feature_geometry, is_multi_geom=True),
        'LineString': GeojsonLine(id, feature_properties, feature_geometry),
        'MultiLineString': GeojsonLine(id, feature_properties, feature_geometry, is_multi_geom=True)
    }[feature_geometry['type']]


def retrieve_geojsons(path):
    files = []
    features = []

    if(os.path.isdir(path)):
        geojson_dir = listdir(path)
        for geojson_file in geojson_dir:
            file_path = os.path.join(path, geojson_file)
            if(os.path.isfile(file_path)):
                if(".geojson" in geojson_file or ".json" in geojson_file):
                    files.append(file_path)
    else:
        files.append(path)

    # Reads and parse every features from the file(s)
    for geojson_file in files:
        print("Reading " + geojson_file)
        with open(geojson_file) as f:
            gjContent = json.load(f)

        k = 0
        for feature in gjContent['features']:
            if "ID" in feature['properties']:
                feature_id = feature['properties']['ID']
            else:
                feature_id = 'feature_' + str(k)
                k += 1
            features.append(get_geojson_instance(feature_id, feature['geometry'], feature['properties']))

    return features


def from_geojson_directory(path, properties, obj_name=None, create_lod1=False, create_loa=False, polygons_path=None, is_roof=False):
    """
    :param path: a path to a directory

    :return: a tileset.
    """

    features = retrieve_geojsons(path)
    objects = Geojsons.parse_geojsons(features, properties, obj_name, is_roof)

    if(len(objects) == 0):
        print("No .geojson found in " + path)
        return None
    else:
        print(str(len(objects)) + " features parsed")

    return create_tileset(objects, also_create_lod1=create_lod1, also_create_loa=create_loa, polygons_path=polygons_path)


def main():
    """
    :return: no return value

    this function creates a repository named "geojson_tilesets" that contains a tileset
    created from all the geojson files stored in the targeted directory
    """
    args = parse_command_line()
    path = args.path[0]

    create_loa = args.loa is not None
    properties = ['height', args.height, 'width', args.width, 'prec', args.prec]

    if(os.path.isdir(path) or Path(path).suffix == ".geojson" or Path(path).suffix == ".json"):
        tileset = from_geojson_directory(path, properties, args.obj, args.lod1, create_loa, args.loa, args.is_roof)
        if(tileset is not None):
            tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
            print("tileset in geojson_tilesets")
            tileset.write_to_directory("geojson_tilesets")
    else:
        print(path, "is neither a geojson file or a directory. Please target geojson file or a directory containing geojson files.")


if __name__ == '__main__':
    main()
