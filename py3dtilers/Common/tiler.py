import argparse
from pathlib import Path
import sys
import os

from ..Common import LodTree, FromGeometryTreeToTileset, Groups
from ..Color import ColorConfig
from ..Texture import Texture
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from ..Common import FeatureList


class Tiler():

    # The kd_tree_max is the maximum number of features that the kd-tree will put in each tile.
    DEFAULT_KD_TREE_MAX = 500

    def __init__(self):
        text = '''A small utility that build a 3DTiles tileset out of data'''
        self.supported_extensions = []
        self.default_input_path = None
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

        self.parser.add_argument('--height_mult',
                                 nargs='?',
                                 type=float,
                                 default=1.0,
                                 help='Multipler can be used if height values are in different units. For example, if height is in survey feet, you will need to use 0.3048006096 as multipler.')

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

        self.parser.add_argument('--no_normals',
                                 dest='no_normals',
                                 action='store_true',
                                 help='If specified, no normals will be written to glTf, useful for Photogrammetry meshes')

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

        self.parser.add_argument('--paths',
                                 '--path',
                                 '--db_config_path',
                                 '--file_path',
                                 '-i',
                                 nargs='*',
                                 type=str,
                                 help='Paths to input files or directories.')

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

        self.parser.add_argument('--texture_lods',
                                 '--tl',
                                 nargs='?',
                                 type=int,
                                 default=0,
                                 help='Set the number of levels of detail that will be created for each textured tile.\
                                     Each level of detail will be a tile with a less detailled image but the same geometry.')

        self.parser.add_argument('--keep_ids',
                                 nargs='*',
                                 default=[],
                                 type=str,
                                 help='If present, keep only the features which have their ID in the list.')

        self.parser.add_argument('--exclude_ids',
                                 nargs='*',
                                 default=[],
                                 type=str,
                                 help='If present, exlude the features which have their ID in the list.')

        self.parser.add_argument('--as_lods',
                                 dest='as_lods',
                                 action='store_true',
                                 help='When used, the inputs are used as LODs.')

    def parse_command_line(self):
        self.args, _ = self.parser.parse_known_args()

        if self.args.paths is None or len(self.args.paths) == 0:
            if self.default_input_path is not None:
                self.args.paths = [self.default_input_path]
            else:
                print("Please provide at least one path to a file or directory")
                print("Exiting")
                sys.exit(1)
        self.retrieve_files(self.args.paths)

        if self.args.obj is not None and '.obj' not in self.args.obj:
            self.args.obj = self.args.obj + '.obj'

        if len(self.args.offset) < 3:
            [self.args.offset.append(0) for _ in range(len(self.args.offset), 3)]
        elif len(self.args.offset) > 3:
            self.args.offset = self.args.offset[:3]
        for i, val in enumerate(self.args.offset):
            if not isinstance(val, (int, float)) and val.lstrip('-').replace('.', '', 1).isdigit():
                self.args.offset[i] = float(val)

        for i, val in enumerate(self.args.geometric_error):
            self.args.geometric_error[i] = int(val) if val is not None and val.isnumeric() else None
        [self.args.geometric_error.append(None) for _ in range(len(self.args.geometric_error), 3)]

        if self.args.quality is not None:
            Texture.set_texture_quality(self.args.quality)
        if self.args.compress_level is not None:
            Texture.set_texture_compress_level(self.args.compress_level)
        if self.args.format is not None:
            Texture.set_texture_format(self.args.format)

    def retrieve_files(self, paths):
        """
        Retrieve the files from paths given by the user.
        :param paths: a list of paths
        """
        self.files = []

        for path in paths:
            if os.path.isdir(path):
                dir = os.listdir(path)
                for file in dir:
                    file_path = os.path.join(path, file)
                    if os.path.isfile(file_path):
                        if Path(file).suffix in self.supported_extensions:
                            self.files.append(file_path)
            else:
                self.files.append(path)
        self.files = sorted(self.files)
        if len(self.files) == 0:
            print("No file with supported extensions was found")
            sys.exit(1)
        else:
            print(len(self.files), "file(s) with supported extensions found")

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

    def create_tileset_from_feature_list(self, feature_list: 'FeatureList', extension_name=None):
        """
        Create the 3DTiles tileset from the features.
        :param feature_list: a FeatureList
        :param extension_name: an optional extension to add to the tileset
        :return: a TileSet
        """
        if len(feature_list) == 0:
            print("No feature found in source")
            sys.exit(1)
        else:
            if len(self.args.keep_ids) > 0:
                feature_list.filter(lambda id: id in self.args.keep_ids)
            if len(self.args.exclude_ids) > 0:
                feature_list.filter(lambda id: id not in self.args.exclude_ids)
            if len(feature_list) == 0:
                print("No feature left, exiting")
                sys.exit(1)
            print("Distribution of the", len(feature_list), "feature(s)...")
        groups = Groups(feature_list, self.args.loa, self.get_kd_tree_max(), self.args.as_lods).get_groups_as_list()
        feature_list.delete_features_ref()
        return self.create_tileset_from_groups(groups, extension_name)

    def create_tileset_from_groups(self, groups: Groups, extension_name=None):
        """
        Create the 3DTiles tileset from the groups.
        :param groups: Groups
        :param extension_name: an optional extension to add to the tileset
        :return: a TileSet
        """
        create_loa = self.args.loa is not None
        geometric_errors = self.args.geometric_error if hasattr(self.args, 'geometric_error') else [None, None, None]
        with_normals = False if self.args.no_normals else True

        if self.args.as_lods:
            tree = LodTree.vertical_hierarchy(groups, geometric_errors)
        else:
            tree = LodTree(groups, self.args.lod1, create_loa, self.args.with_texture, geometric_errors, self.args.texture_lods)

        self.create_output_directory()
        return FromGeometryTreeToTileset.convert_to_tileset(tree, self.args, extension_name, self.get_output_dir(), with_normals=with_normals)

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
