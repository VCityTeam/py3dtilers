import sys

from py3dtiles import TilesetReader, TileSet
from .tileset_tree import TilesetTree
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

        if(self.args.path is None):
            print("Please provide a path to a tileset.json file.")
            print("Exiting")
            sys.exit(1)

    def create_tileset_from_geometries(self, tileset_tree, extension_name=None):
        """
        Override the parent tileset creation.
        """
        if hasattr(self.args, 'scale') and self.args.scale:
            for objects in tileset_tree.get_all_objects():
                objects.scale_objects(self.args.scale)

        if not all(v == 0 for v in self.args.offset) or self.args.offset[0] == 'centroid':
            if self.args.offset[0] == 'centroid':
                self.args.offset = tileset_tree.centroid
            for objects in tileset_tree.get_all_objects():
                objects.translate_objects(self.args.offset)

        if not self.args.crs_in == self.args.crs_out:
            for objects in tileset_tree.get_all_objects():
                self.change_projection(objects, self.args.crs_in, self.args.crs_out)

        if self.args.obj is not None:
            self.write_geometries_as_obj(tileset_tree.get_leaf_objects(), self.args.obj)

        return FromGeometryTreeToTileset.convert_to_tileset(tileset_tree, extension_name)

    def transform_tileset(self, tileset):
        """
        Creates a TilesetTree where each node has ObjectsToTile.
        Then, apply transformations (reprojection, translation, etc) on the ObjectsToTile.
        :param tileset: the TileSet to transform

        :return: a TileSet
        """
        tileset_tree = TilesetTree(tileset, self.tileset_of_root_tiles)
        return self.create_tileset_from_geometries(tileset_tree)

    def read_and_merge_tilesets(self, paths_to_tilesets=list()):
        """
        Read all tilesets and merge them into a single TileSet instance.
        The paths of all tilesets are keeped to be able to find the source of each tile.
        :param paths_to_tilesets: the paths of the tilesets

        :return: a TileSet instance
        """
        final_tileset = TileSet()
        i = 0
        for path in paths_to_tilesets:
            try:
                tileset = self.reader.read_tileset(path)
                root_tile = tileset.get_root_tile()
                if 'children' in root_tile.attributes:
                    for tile in root_tile.attributes['children']:
                        final_tileset.add_tile(tile)
                        self.tileset_of_root_tiles.append(path)
                        i += 1
            except Exception:
                print("Couldn't read the tileset", path)
        return final_tileset


def main():

    tiler = TilesetTiler()
    tiler.parse_command_line()
    paths_to_tilesets = tiler.args.path[0]

    tileset = tiler.read_and_merge_tilesets(paths_to_tilesets)

    tiler.create_directory("tileset_reader_output/")
    tileset = tiler.transform_tileset(tileset)
    tileset.write_to_directory("tileset_reader_output/")


if __name__ == '__main__':
    main()
