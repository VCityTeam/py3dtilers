# -*- coding: utf-8 -*-

import sys
import os
import pathlib
from .threedtiles_notion import ThreeDTilesNotion
from .tile import Tile


class TileSet(ThreeDTilesNotion):

    def __init__(self):
        super().__init__()
        self.attributes["asset"] = {"version": "1.0"}
        self.attributes["geometricError"] = None
        self.attributes["root"] = Tile()

    def set_geometric_error(self, error):
        self.attributes["geometricError"] = error

    def set_transform(self, transform):
        """
        :param transform: a flattened transformation matrix
        :return:
        """
        self.get_root_tile().set_transform(transform)

    def set_root_tile(self, tile):
        if not isinstance(tile, Tile):
            print('Root tile must be of type...Tile.')
            sys.exit(1)
        if 'root' in self.attributes:
            print("Warning: overwriting root tile.")
        self.attributes["root"] = tile

    def get_root_tile(self):
        return self.attributes["root"]

    def add_tile(self, tile):
        if not isinstance(tile, Tile):
            print('Add_tile requires a Tile argument.')
            sys.exit(1)
        self.get_root_tile().add_child(tile)

    def add_asset_extras(self, comment):
        """
        :param comment: the comment on original data, pre-processing, possible
                        ownership to be added as asset extra.
        """
        self.attributes["asset"]["extras"] = {
            "$schema": "http://json-schema.org/draft-04/schema",
            "title": "Extras",
            "description": comment
            }

    def prepare_for_json(self):
        """
        Convert to json string possibly mentioning used schemas
        """
        if not self.attributes["geometricError"]:
            print("Warning: defaulting TileSet's unset 'Geometric Error'.")
            self.set_geometric_error(500.0) # FIXME: chose a decent default
        if not self.get_root_tile():
            print('A TileSet must have a root entry')
            sys.exit(1)

    def sync_with_children(self):
        """
        Synchronize the TileSet (e.g. the root tile bounding volume) with
        the tiles that it holds.
        """
        # TODO FIXME: the following code makes the (generally) wrong
        # assumption that the tile hierarchy happens to be flat (that is
        # expect for the root tile, no other tile contains children sub-tiles).
        # In order to fix this code we must walk on the tree of tiles
        # (probably with a depth-first method) and obtain a bottom up
        # update of the (tile) nodes...

        if 'root' not in self.attributes:
            print('TileSet has not root Tile.')
            sys.exit(1)

        self.get_root_tile().sync_with_children()
        self.sync_extensions(self)

    def write_to_directory(self, directory):
        """
        Write (or overwrite), to the directory whose name is provided, the
        TileSet that is:
          - the tileset as a json file and
          - all the tiles content of the Tiles used by the Tileset.
        :param directory: the target directory name
        """
        # Make sure the TileSet is aligned with its children Tiles.
        self.sync_with_children()

        # Create the output directory
        target_dir = pathlib.Path(directory).expanduser()
        pathlib.Path(target_dir).mkdir(parents=True, exist_ok=True)

        # Prior to writing the TileSet, the future location of the enclosed
        # Tile's content (set as their respective TileContent uri) must be
        # specified:
        all_tiles = self.get_root_tile().get_children()
        for index, tile in enumerate(all_tiles):
            tile.set_content_uri(os.path.join('tiles',
                                              f'{index}.b3dm'))

        # Proceed with the writing of the TileSet per se:
        pathlib.Path(target_dir, 'tiles').mkdir(parents=True, exist_ok=True)
        tileset_file = open(os.path.join(target_dir, 'tileset.json'), 'w')
        tileset_file.write(self.to_json())
        tileset_file.close()

        # Terminate with the writing of the tiles content:
        for index, tile in enumerate(all_tiles):
            tile.write_content(directory)

