import argparse
from pyproj import Transformer
import pathlib

from .tileset_creation import create_tileset
from .obj_writer import ObjWriter
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

    def create_tileset_from_geometries(self, objects_to_tile, extension_name=None):
        if sum(self.args.offset) != 0:
            objects_to_tile.translate_objects(self.args.offset)

        if not self.args.crs_in == self.args.crs_out:
            self.change_projection(objects_to_tile, self.args.crs_in, self.args.crs_out)

        if self.args.obj is not None:
            self.write_geometries_as_obj(objects_to_tile, self.args.obj)

        create_loa = self.args.loa is not None

        return create_tileset(objects_to_tile, self.args.lod1, create_loa, self.args.loa, extension_name, self.args.with_texture)

    def create_directory(self, directory):
        target_dir = pathlib.Path(directory).expanduser()
        pathlib.Path(target_dir).mkdir(parents=True, exist_ok=True)
        target_dir = pathlib.Path(directory + '/tiles').expanduser()
        pathlib.Path(target_dir).mkdir(parents=True, exist_ok=True)
        Texture.set_texture_folder(directory)
