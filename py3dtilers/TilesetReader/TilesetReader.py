import sys

from py3dtiles import TilesetReader
from .parsed_b3dm import ParsedB3dms
from ..Common import Tiler


class B3dmTiler(Tiler):

    def __init__(self):
        super().__init__()

        # adding positional arguments
        self.parser.add_argument('--path',
                                 nargs=1,
                                 type=str,
                                 help='Path to a geojson file or a directory containing geojson files')

        self.parser.add_argument('--merge',
                                 nargs='*',
                                 default=[],
                                 type=str,
                                 help='Path(s) to the additional tileset(s) to merge with the main tileset.')

        self.tile_to_tileset_dict = dict()
        self.tile_index = 0

    def parse_command_line(self):
        super().parse_command_line()

        if(self.args.path is None):
            print("Please provide a path to a tileset.json file.")
            print("Exiting")
            sys.exit(1)

    def get_next_tile_index(self):
        """
        Get the next tile index.
        :return: an index
        """
        index = self.tile_index
        self.tile_index += 1
        return index

    def from_tileset(self, tileset, tileset_paths_dict=None):
        """
        Create a new tileset from another tileset.
        Allows to transform the old tileset before creating a new tileset.
        :param tileset: the tileset to read and transform
        :param tileset_paths_dict: a dict linking tiles with tileset path(s)

        :return: a tileset
        """
        objects = ParsedB3dms(tileset_paths_dict=tileset_paths_dict)
        objects.extend(objects.parse_tileset(tileset))

        return self.create_tileset_from_geometries(objects)

    def merge_tilesets(self, main_tileset, add_tileset_paths=list()):
        """
        Merge additional tilesets to the main tileset.
        :param main_tileset: the main tileset
        :param add_tileset_paths: the path(s) of the additional tileset(s)
        """
        reader = TilesetReader()
        for tileset_path in add_tileset_paths:
            try:
                tileset = reader.read_tileset(tileset_path)
                root_tile = tileset.get_root_tile()
                if 'children' in root_tile.attributes:
                    for tile in root_tile.attributes['children']:
                        main_tileset.add_tile(tile)
                self.link_tile_and_tileset(tileset, tileset_path)
            except Exception:
                print("Couldn't merge the tileset", tileset_path)

    def link_tile_and_tileset(self, tileset, tileset_path):
        """
        Link tile indexes with a tileset path.
        :param tileset: the tileset containing the tiles to link
        :param tileset_path: the path to the tileset
        """
        nb_tiles = len(tileset.get_root_tile().get_children())

        for i in range(0, nb_tiles):
            index = self.get_next_tile_index()
            self.tile_to_tileset_dict[index] = tileset_path


def main():

    tiler = B3dmTiler()
    tiler.parse_command_line()
    path = tiler.args.path[0]
    tiler.create_directory("tileset_reader_output/")
    reader = TilesetReader()
    tileset_1 = reader.read_tileset(path)
    tiler.link_tile_and_tileset(tileset_1, path)

    tilesets_to_merge = tiler.args.merge
    if len(tilesets_to_merge) > 0:
        tiler.merge_tilesets(tileset_1, tilesets_to_merge)

    tileset_2 = tiler.from_tileset(tileset_1, tiler.tile_to_tileset_dict)
    tileset_2.write_to_directory("tileset_reader_output/")


if __name__ == '__main__':
    main()
