import sys
import numpy as np
from io import BytesIO
from PIL import Image, ImageDraw

# This file implement the solution described here
# https://blackpawn.com/texts/lightmaps/
# to properly pack multiple texture in a Atlas by creating a tree
# of rectangle representing the Atlas.

class Rectangle(object):
    """ 
    The class that represents a rectangle in the atlas by its position, width 
    and height. 
    """
    def __init__(self, left, top, right, bottom):
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
        self.width = right - left
        self.height = bottom - top

    def setSize(self, newWidth, newHeight):
        self.width = newWidth
        self.height = newHeight

    def get_top(self):
        return self.top

    def get_bottom(self):
        return self.bottom

    def get_right(self):
        return self.right

    def get_left(self):
        return self.left

    def get_width(self):
        return self.width

    def get_height(self):
        return self.height

    def fits(self,img):
        """
        :param img: A pillow image
        :rtype boolean: Whether the image fits in the rectangle or no
                        i.e if the image is smaller than the rectangle
        """
        imageWidth, imageHeight = img.size
        return imageWidth <= self.width and imageHeight <= self.height

    def perfect_fits(self,img):
        """
        :param img: A pillow image
        :rtype boolean: Whether the image prefectly fits in the rectangle or no, 
                    i.e if the image have the exact same size of the rectangle
        """
        imageWidth, imageHeight = img.size
        return imageWidth == self.width and imageHeight == self.height

class Node(object):
    """ 
    The class that represents a node in the tree representing the Atlas. 
    It should be associate with at least a rectangle.
    """
    tile_number = 0

    def __init__(self,rect = None):
        self.rect = rect
        self.child = [None,None]
        self.image = None
        self.building_id = None
        self.node_number = 0

    def isLeaf(self):
        return (self.child[0] == None and self.child[1] == None)

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

            if newNode != None :
                self.child[0] = newNode
                return self
            else:
                newNode = self.child[1].insert(img, building_id)
                if newNode != None:
                    self.child[1] = newNode
                    return self
                else:
                    return None
        else :
            # return None if the current Node already has an image
            if self.image != None:
                return None

            # If the current image perfectly fits, we stop the insertion here
            # and add the current image to the current node
            if self.rect.perfect_fits(img) == True :
                self.building_id = building_id
                self.image = img
                return self

            # If the current image does not fit in the current node, we can not
            # insert the image in further child nodes
            if self.rect.fits(img) == False :
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

            if dw >= dh :
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
            color = 'black')

        self.fillAtlasImage(atlasImg,city_objects_with_gmlid_key)
        atlasImg.save('junk_buildings/tiles/ATLAS_' + str(tile_number) + '.png')

    def fillAtlasImage(self, atlasImg,city_objects_with_gmlid_key):
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
            if self.image != None :
                atlasImg.paste(
                    self.image, 
                    (self.rect.get_left(), self.rect.get_top())
                    )

                self.updateUv(
                    city_objects_with_gmlid_key[self.building_id].triangles[1],
                    self.image,
                    atlasImg)
        else :
            self.child[0].fillAtlasImage(atlasImg, city_objects_with_gmlid_key)
            self.child[1].fillAtlasImage(atlasImg, city_objects_with_gmlid_key)


    def updateUv(self, uvs, oldTexture, newTexture):
        """
        :param uvs : an UV array
        :param oldTexture : a pillow image, representing the old texture 
                        associated to the uvs
        :param newTexture : a pillow image, representing the new texture 
        """
        oldWidth, oldHeight= (oldTexture.size)
        newWidth, newHeight= (newTexture.size)

        ratioWidth = oldWidth/newWidth
        ratioHeight = oldHeight/newHeight

        offsetWidth = (self.rect.get_left()/newWidth)
        offsetHeight = (self.rect.get_top()/newHeight)

        for i in range(0,len(uvs)):
            for y in range(0,3):
                new_u = (uvs[i][y][0] * ratioWidth) + offsetWidth
                new_v = (uvs[i][y][1] * ratioHeight) + offsetHeight
                # warning : in order to be written correctly, the GLTF writter 
                # expects data to be in float32
                uvs[i][y] = np.array([new_u, new_v], dtype=np.float32)

def updateUvs(uvs, rect):
    offsetX = rect[0]
    offsetY = rect[1]
    if rect[2] != rect[0]:
        ratioX = 1 / (rect[2] - rect[0])
    else:
        ratioX = 1
    if rect[3] != rect[1]:
        ratioY = 1 / (rect[3] - rect[1])
    else:
        ratioY = 1

    for i in range(0,len(uvs)):
        for y in range(0,3):
            new_u = (uvs[i][y][0] - offsetX) * ratioX
            new_v = (uvs[i][y][1] - offsetY) * ratioY
            # warning : in order to be written correctly, the GLTF writter 
            # expects data to be in float32
            uvs[i][y] = np.array([new_u, new_v], dtype=np.float32)

def computeArea(size):
    """
    :param size : an array with a width and a height of a texture
    :rtype float: the area of the texture
    """
    width, height = size
    return width * height

def getTexture(textureUri, objects_type, cursor, triangles):
    """
    :param textureUri : a texture Uri in the database
    :param objects_type: a class name among CityMCityObject derived classes.
                    For example, objects_type can be "CityMBuilding".
    :param cursor: a database access cursor
    :rtype pillow.image:
    """
    imageBinaryData = objects_type.retrieve_textures(
        cursor,
        textureUri,
        objects_type)
    LEFT_THUMB = imageBinaryData[0][0]
    stream = BytesIO(LEFT_THUMB)
    image = Image.open(stream).convert("RGBA")

    return cropImage(image, triangles)

def cropImage(image, triangles):
    minX = 2
    maxX = -1

    minY = 2
    maxY = -1
    
    texture_size = image.size
    for uv_triangle in triangles:
        for uv in uv_triangle:
            if uv[0] < minX:
                minX = uv[0]
            if uv[0] > maxX:
                maxX = uv[0]                    
            if uv[1] < minY:
                minY = uv[1]
            if uv[1] > maxY:
                maxY = uv[1]

    cropped_image = image.crop((minX*texture_size[0],minY*texture_size[1],maxX*texture_size[0],maxY*texture_size[1]))

    updateUvs(triangles,[minX,minY,maxX,maxY])
    return cropped_image

def multipleOf2(nb):
    """
    :param nb: a number
    :rtype float: The first multiple of 2 greater than the number
    """
    i = 1
    while i < nb :
        i*=2
    return i

def computeAtlasTree(textures_sorted):
    """
    :param textures_sorted:  A dictionnary, with building_id as key, 
                        and pillow image as value.
    :rtype node: the root node of the atlas tree
    """
    surfaceAtlas = 0
    for key, image in textures_sorted:
        # Add the surface of the current texture to the atlas one
        surfaceAtlas+= computeArea(image.size)

    # We estimate the size of the atlas to be around the nearest power of 2 
    # of the squareroot of all surfaces combined. There will be cases 
    # where this does not work, since this creates a square.  
    sizeOfAtlas = multipleOf2(np.sqrt(surfaceAtlas))

    rect = Rectangle(0,0,(sizeOfAtlas//2)+1,(sizeOfAtlas//2)+1)
    node_root = None
    it = 0
    while node_root == None :
        node_root = Node(rect)
        axis = it % 2
        axisX = 1 - axis
        axisY = 1 - (1 - axis)
        for key, image in textures_sorted:
            node_root = node_root.insert(image,key)
            if node_root == None:
                # If the node_root is None, this means that the estimation 
                # of the size of the atlas is wrong and must be enlarged
                rect = Rectangle(
                            0,
                            0,
                            int(rect.get_width() + rect.get_width() * 0.5 * axisX),
                            int(rect.get_height() + rect.get_height() * 0.5 * axisY)
                            )
                it += 1
                break
    node_root.set_tile_number()
    return node_root

def createTextureAtlas(objects):
    objects_with_id_key = dict()
    textures_with_id_key = dict()

    for object_to_tile in objects:
        objects_with_id_key[object_to_tile.get_id()] = object_to_tile.geom
        textures_with_id_key[object_to_tile.get_id()] = object_to_tile.get_texture()

    # Sort textures by size, starting by the biggest one
    textures_sorted = sorted(textures_with_id_key.items(), 
                        key=lambda t: computeArea(t[1].size), reverse=True)

    atlasTree = computeAtlasTree(textures_sorted)       
    tile_number = atlasTree.get_tile_number()

    atlasTree.createAtlasImage(objects_with_id_key, tile_number)
    
    return tile_number
