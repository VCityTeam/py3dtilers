import argparse
import shutil
import os
from pathlib import Path
from py3dtiles import TilesetReader, TileSet, BoundingVolumeBox


class TilesetMerger():

    def __init__(self, output_path="tileset_merger_output"):
        self.output_path = output_path
        self.reader = TilesetReader()

    def parse_paths(self):
        """
        Parse the arguments in command line and return the paths.
        :return: a list of paths
        """
        parser = argparse.ArgumentParser()
        parser.add_argument('--paths',
                            '-i',
                            nargs='*',
                            type=str,
                            help='Paths to 3DTiles tilesets')
        parser.add_argument('--output_dir',
                            '--out',
                            '-o',
                            nargs='?',
                            type=str,
                            help='Output directory of the tileset.')
        args, _ = parser.parse_known_args()
        if args.output_dir is not None:
            self.output_path = Path(args.output_dir)
        return args.paths

    @staticmethod
    def merge_tilesets(tilesets, tileset_paths):
        """
        Merge all tilesets into a single TileSet instance.
        The paths of all tilesets are keeped to be able to find the source of each tile.
        :param tilesets: a list of TileSet
        :param tileset_paths: the paths of the tilesets

        :return: a TileSet, the paths of the original tilesets of the root tiles
        """
        final_tileset = TileSet()
        tileset_of_root_tiles = list()
        i = 0
        for index, tileset in enumerate(tilesets):
            root_tile = tileset.get_root_tile()
            if 'children' in root_tile.attributes:
                for tile in root_tile.attributes['children']:
                    final_tileset.add_tile(tile)
                    tileset_of_root_tiles.append(tileset_paths[index])
                    i += 1
        final_tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
        return final_tileset, tileset_of_root_tiles

    def copy_tile_texture_images(self, tile, tileset_path, index):
        """
        Copy all texture images of a tile into the output directory.
        The images are renamed to avoid name conflicts between images of different tiles.
        :param tile: a Tile
        :param tileset_path: the path of the original tileset of the tile
        :param index: the index added in the new name of the image
        """
        header = tile.get_content().body.glTF.header
        if 'images' in header:
            for image in header['images']:
                if 'uri' in image:  # copy only external images (i.e. the one that have a uri)
                    path = Path(os.path.join(tileset_path, "tiles", image['uri']))
                    new_uri = f"{path.stem}_{index}_{path.suffix}"
                    image['uri'] = new_uri
                    new_file_path = Path(os.path.join(self.output_path, "tiles"), new_uri)
                    shutil.copyfile(path, new_file_path)

    def copy_tileset_texture_images(self, tileset, tileset_of_root_tiles):
        """
        Copy all texture images of a TileSet into the output directory.
        The paths of the tilesets of the root tiles allow to find the images on the disk.
        :param tileset: a TileSet
        :param tileset_of_root_tiles: the paths to the tilesets of the root tiles
        """
        for i, tile in enumerate(tileset.get_root_tile().attributes['children']):
            tileset_path = tileset_of_root_tiles[i]
            self.copy_tile_texture_images(tile, tileset_path, i)

    def write_merged_tileset(self, tileset, tileset_of_root_tiles):
        """
        Write the TileSet into a directory and copy all texture images into this directory.
        :param tileset: a TileSet
        :param tileset_of_root_tiles: the paths to the original tilesets of each root tile
        """
        if 'children' in tileset.get_root_tile().attributes:
            target_dir = Path(str(self.output_path)).expanduser()
            Path(target_dir).mkdir(parents=True, exist_ok=True)
            target_dir = Path(str(self.output_path), 'tiles').expanduser()
            Path(target_dir).mkdir(parents=True, exist_ok=True)

            self.copy_tileset_texture_images(tileset, tileset_of_root_tiles)
            tileset.write_to_directory(self.output_path)


def main():
    merger = TilesetMerger("tileset_merger_output")
    paths = merger.parse_paths()
    tilesets = merger.reader.read_tilesets(paths)
    tileset, root_tiles_paths = merger.merge_tilesets(tilesets, paths)
    merger.write_merged_tileset(tileset, root_tiles_paths)


if __name__ == '__main__':
    main()
