import numpy as np
from pathlib import Path
from PIL import Image
from ..Texture import Rectangle, Texture


class Node(object):
    """
    The class that represents a node in the tree representing the Atlas.
    It should be associate with at least a rectangle.
    """
    tile_number = 0

    def __init__(self, rect=None):
        self.rect = rect
        self.child = [None, None]
        self.image = None
        self.feature_id = None
        self.node_number = 0

    def isLeaf(self):
        return (self.child[0] is None and self.child[1] is None)

    def set_tile_number(self):
        self.node_number = Node.tile_number
        Node.tile_number += 1

    def get_tile_number(self):
        return self.node_number

    def insert(self, img, feature_id):
        """
        :param img: A pillow image
        :param feature_id: A feature_id,
                        in order to be able to modify the UV later
        :rtype node: The tree by returning the calling node
                    when the image is insert in it. It is computed recursively.
        """
        if not self.isLeaf():
            newNode = self.child[0].insert(img, feature_id)

            if newNode is not None:
                self.child[0] = newNode
                return self
            else:
                newNode = self.child[1].insert(img, feature_id)
                if newNode is not None:
                    self.child[1] = newNode
                    return self
                else:
                    return None
        else:
            # return None if the current Node already has an image
            if self.image is not None:
                return None

            # If the current image perfectly fits, we stop the insertion here
            # and add the current image to the current node
            if self.rect.perfect_fits(img):
                self.feature_id = feature_id
                self.image = img
                return self

            # If the current image does not fit in the current node, we can not
            # insert the image in further child nodes
            if not self.rect.fits(img):
                return None

            # If the current rectangle is bigger than the image, we then need to
            # create two child nodes, and insert the image in the first one
            self.child[0] = Node()
            self.child[1] = Node()

            width, height = img.size

            # Compute the difference in height and widht between the current
            # rectangle and image to insert in order to cut the current rectangle
            # either in vertical or horizontal and create two child nodes.
            dw = self.rect.get_width() - width
            dh = self.rect.get_height() - height

            if dw >= dh:
                self.child[0].rect = Rectangle(
                    self.rect.get_left(),
                    self.rect.get_top(),
                    self.rect.get_left() + width,
                    self.rect.get_bottom())
                self.child[1].rect = Rectangle(
                    self.rect.get_left() + width + 1,
                    self.rect.get_top(),
                    self.rect.get_right(),
                    self.rect.get_bottom())
            if dw < dh:
                self.child[0].rect = Rectangle(
                    self.rect.get_left(),
                    self.rect.get_top(),
                    self.rect.get_right(),
                    self.rect.get_top() + height)
                self.child[1].rect = Rectangle(
                    self.rect.get_left(),
                    self.rect.get_top() + height + 1,
                    self.rect.get_right(),
                    self.rect.get_bottom())

            # The first child is created in a way that the image always can be
            # inserted in it.
            self.child[0].insert(img, feature_id)
            return self

    def createAtlasImage(self, features_with_id_key, tile_number, downsample_factor=1):
        """
        :param features_with_id_key: a dictionnary, with feature_id as key,
                        and triangles as value. The triangles position must be
                        in triangles[0] and the UV must be in
                        triangles[1]
        :param tile_number: the tile number
        :param int downsample_factor: the factor used to downsize the image
        """
        atlasImg = Image.new(
            'RGB',
            (self.rect.get_width(), self.rect.get_height()),
            color='black')

        self.fillAtlasImage(atlasImg, features_with_id_key)
        atlas_id = 'ATLAS_' + str(tile_number) + Texture.format

        if downsample_factor != 1:
            width = 1 << (int(atlasImg.width / downsample_factor) - 1).bit_length()
            height = 1 << (int(atlasImg.height / downsample_factor) - 1).bit_length()
            atlasImg = atlasImg.resize((width, height))
        atlasImg.save(Path(Texture.folder, 'tiles', atlas_id), quality=Texture.quality, compress_level=Texture.compress_level)
        return atlas_id

    def fillAtlasImage(self, atlasImg, features_with_id_key):
        """
        :param atlasImg: An empty pillow image that will be filled
                        with each textures in the tree
        :param features_with_id_key: a dictionnary, with feature_id as key,
                        and triangles as value. The triangles position must be
                        in triangles[0] and the UV must be in
                        triangles[1]
        """
        if self.isLeaf():
            if self.image is not None:
                atlasImg.paste(
                    self.image,
                    (self.rect.get_left(), self.rect.get_top())
                )

                self.updateUv(
                    features_with_id_key[self.feature_id].triangles[1],
                    self.image,
                    atlasImg)
        else:
            self.child[0].fillAtlasImage(atlasImg, features_with_id_key)
            self.child[1].fillAtlasImage(atlasImg, features_with_id_key)

    def updateUv(self, uvs, oldTexture, newTexture):
        """
        :param uvs : an UV array
        :param oldTexture : a pillow image, representing the old texture
                        associated to the uvs
        :param newTexture : a pillow image, representing the new texture
        """
        oldWidth, oldHeight = (oldTexture.size)
        newWidth, newHeight = (newTexture.size)

        ratioWidth = oldWidth / newWidth
        ratioHeight = oldHeight / newHeight

        offsetWidth = (self.rect.get_left() / newWidth)
        offsetHeight = (self.rect.get_top() / newHeight)

        for i in range(0, len(uvs)):
            for y in range(0, 3):
                new_u = (uvs[i][y][0] * ratioWidth) + offsetWidth
                new_v = (uvs[i][y][1] * ratioHeight) + offsetHeight
                uvs[i][y] = np.array([new_u, new_v])
