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

    def parse_command_line(self):
        super().parse_command_line()

        if(self.args.path is None):
            print("Please provide a path to a tileset.json file.")
            print("Exiting")
            sys.exit(1)

    def from_tileset(self, tileset, tileset_path=None):
        objects = ParsedB3dms(tileset_path=tileset_path)
        objects.extend(objects.parse_tileset(tileset))

        return self.create_tileset_from_geometries(objects)


def main():

    tiler = B3dmTiler()
    tiler.parse_command_line()
    path = tiler.args.path[0]
    tiler.create_directory("tileset_reader_output/")
    reader = TilesetReader()
    tileset_1 = reader.read_tileset(path)
    tileset_2 = tiler.from_tileset(tileset_1, path)
    tileset_2.write_to_directory("tileset_reader_output/")


if __name__ == '__main__':
    main()
