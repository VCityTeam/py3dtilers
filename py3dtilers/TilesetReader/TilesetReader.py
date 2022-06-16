import sys

from py3dtiles import TilesetReader
from .tileset_tree import TilesetTree
from .TilesetMerger import TilesetMerger
from ..Common import Tiler, FromGeometryTreeToTileset


class TilesetTiler(Tiler):

    def __init__(self):
        super().__init__()

        # adding positional arguments
        self.parser.add_argument('--paths',
                                 nargs='*',
                                 type=str,
                                 help='Paths to 3DTiles tilesets')

        self.tileset_of_root_tiles = list()
        self.reader = TilesetReader()

    def parse_command_line(self):
        super().parse_command_line()

        if(len(self.args.paths) < 1):
            print("Please provide a path to directory containing the root of your 3DTiles.")
            print("Exiting")
            sys.exit(1)

    def get_output_dir(self):
        """
        Return the directory name for the tileset.
        """
        if self.args.output_dir is None:
            return "tileset_reader_output"
        else:
            return self.args.output_dir

    def create_tileset_from_feature_list(self, tileset_tree, extension_name=None):
        """
        Override the parent tileset creation.
        """
        self.create_output_directory()
        return FromGeometryTreeToTileset.convert_to_tileset(tileset_tree, self.args, extension_name, self.get_output_dir())

    def transform_tileset(self, tileset):
        """
        Creates a TilesetTree where each node has FeatureList.
        Then, apply transformations (reprojection, translation, etc) on the FeatureList.
        :param tileset: the TileSet to transform

        :return: a TileSet
        """
        geometric_errors = self.args.geometric_error if hasattr(self.args, 'geometric_error') else [None, None, None]
        tileset_tree = TilesetTree(tileset, self.tileset_of_root_tiles, geometric_errors)
        return self.create_tileset_from_feature_list(tileset_tree)

    def read_and_merge_tilesets(self, paths_to_tilesets=list()):
        """
        Read all tilesets and merge them into a single TileSet instance with the TilesetMerger.
        The paths of all tilesets are keeped to be able to find the source of each tile.
        :param paths_to_tilesets: the paths of the tilesets

        :return: a TileSet
        """
        tilesets = self.reader.read_tilesets(paths_to_tilesets)
        tileset, self.tileset_of_root_tiles = TilesetMerger.merge_tilesets(tilesets, paths_to_tilesets)
        return tileset


def main():

    tiler = TilesetTiler()
    tiler.parse_command_line()

    tileset = tiler.read_and_merge_tilesets(tiler.args.paths)

    tileset = tiler.transform_tileset(tileset)
    tileset.write_as_json(tiler.get_output_dir())


if __name__ == '__main__':
    main()
