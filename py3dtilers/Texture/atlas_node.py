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
        self.building_id = None
        self.node_number = 0

    def isLeaf(self):
        return (self.child[0] is None and self.child[1] is None)

    def set_tile_number(self):
        self.node_number = Node.tile_number
        Node.tile_number += 1

    def get_tile_number(self):
        return self.node_number

    def insert(self, img, building_id):
        """
        :param img: A pillow image
        :param building_id: A building_id,
                        in order to be able to modify the UV later
        :rtype node: The tree by returning the calling node
                    when the image is insert in it. It is computed recursively.
        """
        if not self.isLeaf():
            newNode = self.child[0].insert(img, building_id)

            if newNode is not None:
                self.child[0] = newNode
                return self
            else:
                newNode = self.child[1].insert(img, building_id)
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
                self.building_id = building_id
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
            self.child[0].insert(img, building_id)
            return self

    def createAtlasImage(self, city_objects_with_gmlid_key, tile_number):
        """
        :param city_objects_with_gmlid_key: the geometry of the tile retrieved
                        from the database.
                        It is a dictionnary, with building_id as key,
                        and triangles as value. The triangles position must be
                        in triangles[0] and the UV must be in
                        triangles[1]
        :param tile_number: the tile number
        """
        atlasImg = Image.new(
            'RGB',
            (self.rect.get_width(), self.rect.get_height()),
            color='black')

        self.fillAtlasImage(atlasImg, city_objects_with_gmlid_key)
        atlasImg.save(Path(Texture.folder, 'tiles', 'ATLAS_' + str(tile_number) + '.png'))

    def fillAtlasImage(self, atlasImg, city_objects_with_gmlid_key):
        """
        :param atlasImg: An empty pillow image that will be filled
                        with each textures in the tree
        :param city_objects_with_gmlid_key: the geometry of the tile retrieved
                        from the database.
                        It is a dictionnary, with building_id as key,
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
                    city_objects_with_gmlid_key[self.building_id].triangles[1],
                    self.image,
                    atlasImg)
        else:
            self.child[0].fillAtlasImage(atlasImg, city_objects_with_gmlid_key)
            self.child[1].fillAtlasImage(atlasImg, city_objects_with_gmlid_key)

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
                # warning : in order to be written correctly, the GLTF writter
                # expects data to be in float32
                uvs[i][y] = np.array([new_u, new_v], dtype=np.float32)
