import argparse
from pyproj import Transformer
import pathlib

from ..Common import LodTree, ObjWriter, FromGeometryTreeToTileset
from ..Color import ColorConfig
from ..Texture import Texture


class Tiler():

    def __init__(self):
        text = '''A small utility that build a 3DTiles tileset out of data'''
        self.parser = argparse.ArgumentParser(description=text)

        self.parser.add_argument('--obj',
                                 nargs='?',
                                 type=str,
                                 help='When defined, also create an .obj model of the features.\
                                    The flag must be followed by the name of the obj that will be created.')

        self.parser.add_argument('--loa',
                                 nargs='?',
                                 type=str,
                                 help='Creates a LOA when defined. The LOA is a 3D extrusion of polygons.\
                                    Objects in the same polygon are merged together.\
                                    Must be followed by the path to directory containing the polygons .geojson')

        self.parser.add_argument('--lod1',
                                 dest='lod1',
                                 action='store_true',
                                 help='Creates a LOD1 when defined. The LOD1 is a 3D extrusion of the footprint of each object.')

        self.parser.add_argument('--offset',
                                 nargs='*',
                                 default=[0, 0, 0],
                                 type=float,
                                 help='Substract an offset to all the vertices.')

        self.parser.add_argument('--scale',
                                 nargs='?',
                                 type=float,
                                 help='Scale geometries by the input factor.')

        self.parser.add_argument('--crs_in',
                                 nargs='?',
                                 default='EPSG:3946',
                                 type=str,
                                 help='Input projection.')

        self.parser.add_argument('--crs_out',
                                 nargs='?',
                                 default='EPSG:3946',
                                 type=str,
                                 help='Output projection.')

        self.parser.add_argument('--with_texture',
                                 dest='with_texture',
                                 action='store_true',
                                 help='Adds texture to 3DTiles when defined')

    def parse_command_line(self):
        self.args = self.parser.parse_args()

        if(self.args.obj is not None and '.obj' not in self.args.obj):
            self.args.obj = self.args.obj + '.obj'

        if(len(self.args.offset) < 3):
            for i in range(len(self.args.offset), 3):
                self.args.offset.append(0)
        elif(len(self.args.offset) > 3):
            self.args.offset = self.args.offset[:3]

    def write_geometries_as_obj(self, geometries, file_name):
        obj_writer = ObjWriter()
        obj_writer.add_geometries(geometries.get_objects())
        obj_writer.write_obj(file_name)

    def change_projection(self, geometries, crs_in, crs_out):
        transformer = Transformer.from_crs(crs_in, crs_out)
        geometries.change_crs(transformer)

    def create_tree(self, objects_to_tile, create_lod1=False, create_loa=False, polygons_path=None, with_texture=False):
        lod_tree = LodTree(objects_to_tile, create_lod1, create_loa, polygons_path, with_texture)
        return lod_tree

    def create_tileset_from_geometries(self, objects_to_tile, extension_name=None):
        if hasattr(self.args, 'scale') and self.args.scale:
            objects_to_tile.scale_objects(self.args.scale)

        if not all(v == 0 for v in self.args.offset) or self.args.offset[0] == 'centroid':
            if self.args.offset[0] == 'centroid':
                self.args.offset = objects_to_tile.get_centroid()
            objects_to_tile.translate_objects(self.args.offset)

        if not self.args.crs_in == self.args.crs_out:
            self.change_projection(objects_to_tile, self.args.crs_in, self.args.crs_out)

        if self.args.obj is not None:
            self.write_geometries_as_obj(objects_to_tile, self.args.obj)

        create_loa = self.args.loa is not None

        tree = self.create_tree(objects_to_tile, self.args.lod1, create_loa, self.args.loa, self.args.with_texture)
        return FromGeometryTreeToTileset.convert_to_tileset(tree, extension_name)

    def create_directory(self, directory):
        target_dir = pathlib.Path(directory).expanduser()
        pathlib.Path(target_dir).mkdir(parents=True, exist_ok=True)
        target_dir = pathlib.Path(directory + '/tiles').expanduser()
        pathlib.Path(target_dir).mkdir(parents=True, exist_ok=True)
        Texture.set_texture_folder(directory)

    def get_color_config(self, config_path):
        return ColorConfig(config_path)
