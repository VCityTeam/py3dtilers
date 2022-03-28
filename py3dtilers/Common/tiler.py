import argparse
from pathlib import Path

from ..Common import LodTree, FromGeometryTreeToTileset
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
                                 help='Substract an offset to all the vertices.')

        self.parser.add_argument('--scale',
                                 nargs='?',
                                 type=float,
                                 help='Scale features by the input factor.')

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

        self.parser.add_argument('--output_dir',
                                 '--out',
                                 '-o',
                                 nargs='?',
                                 type=str,
                                 help='Output directory of the tileset.')

        self.parser.add_argument('--geometric_error',
                                 nargs='*',
                                 default=[None, None, None],
                                 help='The geometric errors of the nodes.\
                                     Used (from left ro right) for basic nodes, LOD1 nodes and LOA nodes.')

    def parse_command_line(self):
        self.args = self.parser.parse_args()

        if(self.args.obj is not None and '.obj' not in self.args.obj):
            self.args.obj = self.args.obj + '.obj'

        if(len(self.args.offset) < 3):
            [self.args.offset.append(0) for _ in range(len(self.args.offset), 3)]
        elif(len(self.args.offset) > 3):
            self.args.offset = self.args.offset[:3]
        for i, val in enumerate(self.args.offset):
            if not isinstance(val, (int, float)) and val.lstrip('-').replace('.', '', 1).isdigit():
                self.args.offset[i] = float(val)

        for i, val in enumerate(self.args.geometric_error):
            self.args.geometric_error[i] = int(val) if val is not None and val.isnumeric() else None
        [self.args.geometric_error.append(None) for _ in range(len(self.args.geometric_error), 3)]

    def get_output_dir(self):
        """
        Return the directory name for the tileset.
        """
        if self.args.output_dir is None:
            return "output_tileset"
        else:
            return self.args.output_dir

    def create_tree(self, feature_list, create_lod1=False, create_loa=False, polygons_path=None, with_texture=False, kd_tree_max=500, geometric_errors=[None, None, None]):
        lod_tree = LodTree(feature_list, create_lod1, create_loa, polygons_path, with_texture, kd_tree_max, geometric_errors)
        return lod_tree

    def create_tileset_from_geometries(self, feature_list, extension_name=None, kd_tree_max=500):
        """
        Create the 3DTiles tileset from the features.
        :param feature_list: a FeatureList
        :param extension_name: an optional extension to add to the tileset
        :param kd_tree_max: the maximum number of features in each list created by the kd_tree
        :return: a TileSet
        """
        create_loa = self.args.loa is not None
        geometric_errors = self.args.geometric_error if hasattr(self.args, 'geometric_error') else [None, None, None]
        tree = self.create_tree(feature_list, self.args.lod1, create_loa, self.args.loa, self.args.with_texture, kd_tree_max, geometric_errors)

        feature_list.delete_objects_ref()
        self.create_output_directory()
        return FromGeometryTreeToTileset.convert_to_tileset(tree, self.args, extension_name, self.get_output_dir())

    def create_output_directory(self):
        """
        Create the directory where the tileset will be writen.
        """
        dir = self.get_output_dir()
        target_dir = Path(dir).expanduser()
        Path(target_dir).mkdir(parents=True, exist_ok=True)
        target_dir = Path(dir, 'tiles').expanduser()
        Path(target_dir).mkdir(parents=True, exist_ok=True)
        Texture.set_texture_folder(dir)

    def get_color_config(self, config_path):
        """
        Return the ColorConfig used to create the colored materials.
        :return: a ColorConfig
        """
        return ColorConfig(config_path)
