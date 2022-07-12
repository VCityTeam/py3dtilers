import argparse
from pathlib import Path

from ..Common import LodTree, FromGeometryTreeToTileset, Groups
from ..Color import ColorConfig
from ..Texture import Texture


class Tiler():

    # The kd_tree_max is the maximum number of features that the kd-tree will put in each tile.
    DEFAULT_KD_TREE_MAX = 500

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
                                 help='Add an offset to all the vertices.')

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

        self.parser.add_argument('--quality',
                                 nargs='?',
                                 type=int,
                                 help='Set the quality of the atlas images. The minimum value is 1 and the maximum 100.\
                                    Quality can only be used with the JPEG format.')

        self.parser.add_argument('--compress_level',
                                 nargs='?',
                                 type=int,
                                 help='Set the compression level of the atlas images. The minimum value is 0 and the maximum 9.\
                                    Compress level can only be used with the PNG format.')

        self.parser.add_argument('--format',
                                 nargs='?',
                                 type=str,
                                 choices=['jpg', 'JPG', 'jpeg', 'JPEG', 'png', 'PNG'],
                                 help='Set the image file format (PNG or JPEG).')

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

        self.parser.add_argument('--kd_tree_max',
                                 nargs='?',
                                 type=int,
                                 help='Set the maximum number of features in each tile when the features are distributed by a kd-tree.\
                                     The value must be an integer.')

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

        if(self.args.quality is not None):
            Texture.set_texture_quality(self.args.quality)
        if(self.args.compress_level is not None):
            Texture.set_texture_compress_level(self.args.compress_level)
        if(self.args.format is not None):
            Texture.set_texture_format(self.args.format)

    def get_output_dir(self):
        """
        Return the directory name for the tileset.
        """
        if self.args.output_dir is None:
            return "output_tileset"
        else:
            return self.args.output_dir

    def get_kd_tree_max(self):
        """
        The kd_tree_max is the maximum number of features in each tile when the features are distributed by a kd-tree.
        If the user has specified a value for the kd_tree_max argument, use that value. Otherwise, use the
        default value.
        :return: a int
        """
        ktm_arg = self.args.kd_tree_max
        kd_tree_max = ktm_arg if ktm_arg is not None and ktm_arg > 0 else self.DEFAULT_KD_TREE_MAX
        return kd_tree_max

    def create_tileset_from_feature_list(self, feature_list, extension_name=None):
        """
        Create the 3DTiles tileset from the features.
        :param feature_list: a FeatureList
        :param extension_name: an optional extension to add to the tileset
        :return: a TileSet
        """
        groups = Groups(feature_list, self.args.loa, self.get_kd_tree_max()).get_groups_as_list()
        feature_list.delete_features_ref()
        return self.create_tileset_from_groups(groups, extension_name)

    def create_tileset_from_groups(self, groups, extension_name=None):
        """
        Create the 3DTiles tileset from the features.
        :param feature_list: a FeatureList
        :param extension_name: an optional extension to add to the tileset
        :param kd_tree_max: the maximum number of features in each list created by the kd_tree
        :return: a TileSet
        """
        create_loa = self.args.loa is not None
        geometric_errors = self.args.geometric_error if hasattr(self.args, 'geometric_error') else [None, None, None]

        tree = LodTree(groups, self.args.lod1, create_loa, self.args.with_texture, geometric_errors)

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
