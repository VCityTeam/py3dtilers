# -*- coding: utf-8 -*-
import sys
import os
from .bounding_volume import BoundingVolume
from .threedtiles_notion import ThreeDTilesNotion
from .tile_content import TileContent


class Tile(ThreeDTilesNotion):

    def __init__(self):
        super().__init__()
        self.attributes["boundingVolume"] = None
        self.attributes["geometricError"] = None
        self.attributes["refine"] = "ADD"
        self.attributes["content"] = None
        self.attributes["children"] = list()
        # Some possible valid properties left un-delt with
        # viewerRequestVolume
        # self.attributes["transform"] = None

    def set_transform(self, transform):
        """
        :param transform: a flattened transformation matrix
        :return:
        """
        self.attributes["transform"] = [round(float(e), 3) for e in transform]

    def get_transform(self):
        if 'transform' in self.attributes:
            return self.attributes["transform"]
        print("Warning: defaulting the transformation matrix for a Tile.")
        return [1.0, 0.0, 0.0, 0.0,
                0.0, 1.0, 0.0, 0.0,
                0.0, 0.0, 1.0, 0.0,
                0.0, 0.0, 0.0, 1.0]

    def set_bounding_volume(self, bounding_volume):
        self.attributes["boundingVolume"] = bounding_volume

    def get_bounding_volume(self):
        return self.attributes["boundingVolume"]

    def set_content(self, content):
        if self.attributes["content"]:
            print('Warning: overwriting existing Tile content.')
        self.attributes["content"] = content

    def get_content(self):
        return self.attributes["content"]

    def set_geometric_error(self, error):
        self.attributes["geometricError"] = error

    def set_content_uri(self, uri):
        if 'content' not in self.attributes:
            self.set_content (TileContent())
        self.attributes["content"].set_uri(uri)

    def get_content_uri(self):
        if 'content' not in self.attributes:
            print('Tile with unset content.')
            sys.exit(1)
        return self.attributes["content"].get_uri()

    def set_refine_mode(self, mode):
        if mode != 'ADD' and mode != 'REPLACE':
            print(f'Unknown refinement mode {mode}.')
            sys.exit(1)
        self.attributes["refine"] = mode

    def add_child(self, tile):
        self.attributes["children"].append(tile)

    def has_children(self):
        if 'children' in self.attributes and self.attributes["children"]:
            return True
        return False

    def get_children(self):
        """
        :return: the recursive (across the children tree) list of the children
                 tiles
        """
        if not self.has_children():
            print("Warning: should have checked for existing children first?")
            # It could be that prepare_for_json() did some wipe out:
            if not 'children' in self.attributes:
                return list()

        descendants = list()
        for child in self.attributes["children"]:
            # Add the child...
            descendants.append(child)
            # and if (and only if) they are grand-children then recurse
            if child.has_children():
                descendants.extend(child.get_children())
        return descendants

    def sync_with_children(self):
        if not self.has_children():
            # We consider that whatever information is present it is the
            # proper one (in other terms: when they are no sub-tiles this tile
            # is a leaf-tile and thus is has no synchronization to do)
            return
        for child in self.get_children():
            child.sync_with_children()

        # The information that depends on (is defined by) the children
        # nodes is limited to be bounding volume.
        bounding_volume = self.get_bounding_volume()
        if not bounding_volume:
            print('This Tile has no bounding volume: exiting.')
            sys.exit(1)
        if not bounding_volume.is_box():
            print("Don't know how to sync non box bounding volume.")
            sys.exit(1)
        bounding_volume.sync_with_children(self)

        self.sync_extensions(self)

    def prepare_for_json(self):
        if not self.attributes["boundingVolume"]:
            print("Warning: defaulting Tile's unset 'Bounding Volume'.")
            # FIXME: what would be a decent default ?!
            self.attributes["boundingVolume"] = BoundingVolume()
        if not self.attributes["geometricError"]:
            print("Warning: defaulting Tile's unset 'Geometric Error'.")
            # FIXME: what would be a decent default ?!
            self.set_geometric_error(500.0)
        if 'children' in self.attributes and not self.attributes["children"]:
            # The children list exists indeed (for technical reasons) yet it
            # happens to be still empty. This would pollute the json output
            # by adding a "children" entry followed by an empty list. In such
            # case just remove that attributes entry:
            del self.attributes["children"]
        if 'content' in self.attributes and not self.attributes["content"]:
            # Refer to children related above comment (mutatis mutandis):
            del self.attributes["content"]

    def write_content(self, directory):
        """
        Write (or overwrite) the tile _content_ to the directory specified
        as parameter and withing the relative filename designated by
        the tile's content uri. Note that it is the responsibility of the
        owning TileSet to
          - set those uris
          - to explicitly invoke write_content() (this is to be opposed with
            the Tile attributes which get serialized when recursing on the
            TileSet attributes)
            :param directory: the target directory
        """
        file_name = self.get_content_uri()
        if not file_name:
            print("An uri is mandatory for writing Tile content.")
            sys.exit(1)
        file_name = os.path.join(directory, file_name)

        # Make sure the output directory exists (note that target_dir may
        # be a sub-directory of 'directory' because the uri might hold its
        # own path):
        target_dir = os.path.dirname(file_name)
        if not os.path.exists(target_dir):
            os.makedirs(target_dir)

        # Write the tile content of this tile:

        # The following is ad-hoc code for the currently existing b3dm class.
        # FIXME: have the future TileContent class have a write method
        # and simplify the following code accordingly.
        content_file = open(file_name, 'wb')
        content_file.write(self.get_content().to_array())
        content_file.close()
