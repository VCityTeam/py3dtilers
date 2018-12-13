# -*- coding: utf-8 -*-

import sys
import os
import pathlib
from .threedtiles_notion import ThreeDTilesNotion
from .real_tile import TileForReal
from .bounding_volume_box import BoundingVolumeBox


class TileSet(ThreeDTilesNotion):

    def __init__(self):
        super().__init__()
        # FIXME: make assert a 3DTilesNotion
        self.attributes["asset"] = {"version": "1.0"}
        self.attributes["geometricError"] = None
        self.attributes["root"] = TileForReal()

    def set_geometric_error(self, error):
        self.attributes["geometricError"] = error

    def set_root_tile(self, tile):
        if not isinstance(tile, TileForReal):
            print('Root tile must be of type...Tile.')
            sys.exit(1)
        if 'root' in self.attributes:
            print("Warning: overwriting root tile.")
        self.attributes["root"] = tile

    def add_tile(self, tile):
        if not isinstance(tile, TileForReal):
            print('Add_tile requires a Tile argument.')
            sys.exit(1)
        self.attributes["root"].add_child(tile)

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
        if not self.attributes["root"]:
            print('A TileSet must have a root entry')
            sys.exit(1)

    def sync(self):
        """
        Synchronize the TileSet (e.g. the root tile bounding volume) with
        the tiles that it holds.
        """
        if 'root' not in self.attributes:
            print('TileSet has not root Tile.')
            sys.exit(1)

        if self.attributes["root"].get_bounding_volume():
            print('Warning: overwriting bounding volume of root Tile.')

        bounding_box = BoundingVolumeBox()
        for child in self.attributes["root"].get_descendants():
            bounding_volume = child.get_bounding_volume()
            if not bounding_volume.is_box():
                print('Dropping child with non box bounding volume.')
                continue
            bounding_box.add(bounding_volume)
        self.attributes["root"].set_bounding_volume(bounding_box)

    def write_to_directory(self, directory):
        """
        Write (or overwrite), to the directory whose name is provided, the
        TileSet that is:
          - the tileset as a json file and
          - all the tiles content of the Tiles used by the Tileset.
        :param directory: the target directory name
        """
        # Make sure the TileSet is aligned with its children Tiles.
        self.sync()

        # Create the output directory
        target_dir = pathlib.Path(directory).expanduser()
        pathlib.Path(target_dir).mkdir(parents=True, exist_ok=True)

        # Write the TileSet
        pathlib.Path(target_dir, 'tiles').mkdir(parents=True, exist_ok=True)
        tileset_file = open(os.path.join(target_dir, 'tileset.json'), 'w')
        tileset_file.write(self.to_json())
        tileset_file.close()

        # Proceed with writing the tiles content and first specify them where
        # they should be written.
        all_tiles = self.attributes["root"].get_descendants()
        for index, tile in enumerate(all_tiles):
            tile.set_content_uri(os.path.join(directory,
                                              'tiles',
                                              f'{index}.b3dm'))
            tile.write_content()

