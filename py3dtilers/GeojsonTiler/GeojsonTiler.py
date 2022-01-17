import os
import sys
from os import listdir
import json

from pathlib import Path
from py3dtiles import BoundingVolumeBox
from .geojson import Geojsons
from .geojson_line import GeojsonLine
from .geojson_polygon import GeojsonPolygon
from ..Common import Tiler


class GeojsonTiler(Tiler):

    def __init__(self):
        super().__init__()

        # adding positional arguments
        self.parser.add_argument('--path',
                                 nargs=1,
                                 type=str,
                                 help='Path to a geojson file or a directory containing geojson files')

        self.parser.add_argument('--height',
                                 nargs='?',
                                 default='HAUTEUR',
                                 type=str,
                                 help='Change the name of the propertie to look for in the feature for height.\
                                    The value can also be a float or an int, this will set the default height.\
                                    Default property name is HAUTEUR')

        self.parser.add_argument('--width',
                                 nargs='?',
                                 default='LARGEUR',
                                 type=str,
                                 help='Change the name of the propertie to look for in the feature for width.\
                                    The value can also be a float or an int, this will set the default width.\
                                    Default property name is LARGEUR')

        self.parser.add_argument('--prec',
                                 nargs='?',
                                 default='PREC_ALTI',
                                 type=str,
                                 help='Change the name of the propertie to look for in the feature for altitude precision.\
                                    Default property name is PREC_ALTI')

        self.parser.add_argument('--is_roof',
                                 dest='is_roof',
                                 action='store_true',
                                 help='When defined, the features from geojsons will be considered as rooftops.\
                                    We will thus substract the height from the coordinates to reach the floor.')

    def parse_command_line(self):
        super().parse_command_line()

        if(self.args.path is None):
            print("Please provide a path to a directory "
                  "containing some geojson files")
            print("Exiting")
            sys.exit(1)

    def get_geojson_instance(self, id, feature_geometry, feature_properties):
        """
        Create a Geojson instance with the geometry and the properties of a feature.
        :param id: the identifier of the Geojson instance
        :param feature_geometry: the JSON geometry of the feature
        :param feature_properties: the JSON properties of the feature

        :return: a Geojson instance
        """
        return {
            'Polygon': GeojsonPolygon(id, feature_properties, feature_geometry),
            'MultiPolygon': GeojsonPolygon(id, feature_properties, feature_geometry, is_multi_geom=True),
            'LineString': GeojsonLine(id, feature_properties, feature_geometry),
            'MultiLineString': GeojsonLine(id, feature_properties, feature_geometry, is_multi_geom=True)
        }[feature_geometry['type']]

    def retrieve_geojsons(self, path):
        """
        Retrieve the GeoJson features from GeoJson file(s).
        Return a list of Geojson instances containing properties and a geometry.
        :param path: a path to the file(s)

        :return: a list of Geojson instances.
        """
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
                features.append(self.get_geojson_instance(feature_id, feature['geometry'], feature['properties']))

        return features

    def from_geojson_directory(self, path, properties, is_roof=False):
        """
        Create a tileset from a GeoJson file or a directory of GeoJson files
        :param path: a path to the file(s)
        :param properties: the names of the properties to read in the GeoJson file(s)

        :return: a tileset.
        """

        features = self.retrieve_geojsons(path)
        objects = Geojsons.parse_geojsons(features, properties, is_roof)

        if(len(objects) == 0):
            print("No .geojson found in " + path)
            return None
        else:
            print(str(len(objects)) + " features parsed")

        return self.create_tileset_from_geometries(objects)


def main():
    """
    Run the GeojsonTiler: create a 3DTiles tileset from GeoJson file(s).
    The tileset is writen in '/geojson_tilesets/'.
    :return: no return value
    """
    geojson_tiler = GeojsonTiler()
    geojson_tiler.parse_command_line()
    path = geojson_tiler.args.path[0]

    properties = ['height', geojson_tiler.args.height, 'width', geojson_tiler.args.width, 'prec', geojson_tiler.args.prec]

    if(os.path.isdir(path) or Path(path).suffix == ".geojson" or Path(path).suffix == ".json"):
        tileset = geojson_tiler.from_geojson_directory(path, properties, geojson_tiler.args.is_roof)
        if(tileset is not None):
            tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
            print("tileset in geojson_tilesets")
            tileset.write_to_directory("geojson_tilesets")
    else:
        print(path, "is neither a geojson file or a directory. Please target geojson file or a directory containing geojson files.")


if __name__ == '__main__':
    main()
