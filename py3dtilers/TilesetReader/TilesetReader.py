import sys

from py3dtiles import TilesetReader
from .tileset_tree import TilesetTree
from ..Common import Tiler, FromGeometryTreeToTileset


class ThreeDTilesImporter(Tiler):

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

    def from_tileset(self, tileset):
        """
        Create a new tileset from another tileset.
        Allows to transform the old tileset before creating a new tileset.
        :param tileset: the tileset to read and transform

        :return: a tileset
        """
        tileset_tree = TilesetTree(tileset, self.tile_to_tileset_dict)

        return self.create_tileset_from_geometries(tileset_tree)

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

    importer = ThreeDTilesImporter()
    importer.parse_command_line()
    path = importer.args.path[0]
    importer.create_directory("tileset_reader_output/")
    reader = TilesetReader()
    tileset_1 = reader.read_tileset(path)
    importer.link_tile_and_tileset(tileset_1, path)

    tilesets_to_merge = importer.args.merge
    if len(tilesets_to_merge) > 0:
        importer.merge_tilesets(tileset_1, tilesets_to_merge)

    tileset_2 = importer.from_tileset(tileset_1)
    tileset_2.write_to_directory("tileset_reader_output/")


if __name__ == '__main__':
    main()
