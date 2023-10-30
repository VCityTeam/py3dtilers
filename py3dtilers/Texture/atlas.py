import numpy as np
from ..Texture import Rectangle, Node

# This file implement the solution described here
# https://blackpawn.com/texts/lightmaps/
# to properly pack multiple texture in a Atlas by creating a tree
# of rectangle representing the Atlas.


class Atlas():
    """
    An Atlas contains the texture images of a tile.
    """

    def __init__(self, feature_list, downsample_factor=1):
        features_with_id_key = dict()
        textures_with_id_key = dict()

        textures = feature_list.get_textures()
        for feature in feature_list:
            features_with_id_key[feature.get_id()] = feature.geom
            textures_with_id_key[feature.get_id()] = textures[feature.get_id()]

        # Sort textures by size, starting by the biggest one
        textures_sorted = sorted(textures_with_id_key.items(),
                                 key=lambda t: self.computeArea(t[1].size), reverse=True)

        atlasTree = self.computeAtlasTree(textures_sorted)

        self.tile_number = atlasTree.get_tile_number()

        self.id = atlasTree.createAtlasImage(features_with_id_key, self.tile_number, downsample_factor)

    def computeArea(self, size):
        """
        :param size : an array with a width and a height of a texture
        :rtype float: the area of the texture
        """
        width, height = size
        return width * height

    def multipleOf2(self, nb):
        """
        :param nb: a number
        :rtype float: The first multiple of 2 greater than the number
        """
        i = 1
        while i < nb:
            i *= 2
        return i

    def computeAtlasTree(self, textures_sorted):
        """
        :param textures_sorted:  A dictionnary, with building_id as key,
                            and pillow image as value.
        :rtype node: the root node of the atlas tree
        """
        surfaceAtlas = 0
        for key, image in textures_sorted:
            # Add the surface of the current texture to the atlas one
            surfaceAtlas += self.computeArea(image.size)

        # We estimate the size of the atlas to be around the nearest power of 2
        # of the squareroot of all surfaces combined. There will be cases
        # where this does not work, since this creates a square.
        sizeOfAtlas = self.multipleOf2(np.sqrt(surfaceAtlas))

        rect = Rectangle(0, 0, sizeOfAtlas, sizeOfAtlas)
        node_root = None
        it = 0
        while node_root is None:
            node_root = Node(rect)
            axis = it % 2
            for key, image in textures_sorted:
                node_root = node_root.insert(image, key)
                if node_root is None:
                    # If the node_root is None, this means that the estimation
                    # of the size of the atlas is wrong and must be enlarged
                    rect = Rectangle(
                        0,
                        0,
                        int(rect.get_width() + rect.get_width() * (1 - axis)),
                        int(rect.get_height() + rect.get_height() * axis)
                    )
                    it += 1
                    break
        node_root.set_tile_number()
        return node_root
