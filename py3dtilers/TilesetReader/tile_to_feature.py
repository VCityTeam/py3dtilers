import os

from py3dtiles.tilers.b3dm.wkb_utils import TriangleSoup

from .reader_utils import attributes_from_gltf
from ..Common import FeatureList, Feature
from ..Texture import Texture


class TileToFeature(Feature):

    def __init__(self, id=None, triangle_soup=None, mat_index=0):
        super().__init__(id)

        self.geom = triangle_soup
        self.set_box()

    def set_material(self, mat_index, materials, images, tileset_path=None):
        """
        Set the material of this geometry.
        :param mat_index: the index of the material
        :param materials: the list of all the materials
        :param images: the list of all the images
        :param tileset_path: the path to the tileset containing the texture image
        """
        self.material_index = mat_index
        if materials[mat_index].pbrMetallicRoughness.baseColorTexture is not None:
            image_index = materials[mat_index].pbrMetallicRoughness.baseColorTexture.index
            path = os.path.join(tileset_path, "tiles", images[image_index].uri)
            texture = Texture(path)
            self.set_texture(texture.get_cropped_texture_image(self.geom.triangles[1]))

    def set_batchtable_data(self, bt_attributes):
        """
        Set the batch table data of this geometry.
        :param bt_attributes: the batch table attributes for the whole tile
        """
        data = {}
        index = int(self.id)
        for attribute in bt_attributes:
            if attribute == 'ids':
                self.set_id(bt_attributes[attribute][index])
            else:
                data[attribute] = bt_attributes[attribute][index]
        if data:
            super().set_batchtable_data(data)


class TileToFeatureList(FeatureList):

    def __init__(self, tile=None, tileset_path=None):
        self.materials = []
        self.tileset_path = tileset_path
        feature_list = self.__convert_tile(tile)
        super().__init__(feature_list)
        self.set_materials(feature_list.materials)

    def __find_materials(self, gltf):
        """
        Find the materials in the glTF and create Materials.
        :param gltf: the gltf of the tile

        :return: a list of Materials and a list of Images
        """
        materials = gltf.materials
        images = gltf.images
        self.mat_offset = len(self.materials)
        return materials, images

    def __convert_attributes(self, attributes, materials, images):
        """
        Convert the triangle soup to re-create the features.
        :param attributes: atributes dict
        :param materials: the materials of the tile
        :param images: the images of the tile

        :return: a FeatureList instance
        """
        triangles = attributes['positions']
        vertex_ids = attributes['ids']
        vertex_colors = attributes['colors']
        mat_indexes = attributes['mat_indexes']
        uvs = attributes['uvs']

        triangle_dict = dict()
        material_dict = dict()
        for index, triangle in enumerate(triangles):
            id = vertex_ids[3 * index][0]

            if id not in triangle_dict:
                mat_index = int(mat_indexes[int(vertex_ids[3 * index][1])])
                material_dict[id] = mat_index
                triangle_dict[id] = TriangleSoup()
                triangle_dict[id].triangles.append(list())
                if uvs:
                    triangle_dict[id].triangles.append(list())
                if vertex_colors:
                    triangle_dict[id].triangles.append(list())

            triangle_dict[id].triangles[0].append(triangle)
            if uvs:
                triangle_dict[id].triangles[1].append(uvs[index])
            if vertex_colors:
                triangle_dict[id].triangles[1].append(vertex_colors[index])

        objects = []
        for id in triangle_dict:
            feature = TileToFeature(str(int(id)), triangle_dict[id], material_dict[id])
            feature.has_vertex_colors = len(vertex_colors) > 0
            feature.set_material(material_dict[id], materials, images, self.tileset_path)
            objects.append(feature)
        return FeatureList(objects)

    def __convert_tile(self, tile):
        """
        Convert a tile to a FeatureList instance.
        :param tile: the tile to convert

        :return: a FeatureList
        """
        content = tile.get_or_fetch_content(self.tileset_path)
        gltf = content.body.gltf

        materials, images = self.__find_materials(gltf)
        attributes = attributes_from_gltf(gltf)
        feature_list = self.__convert_attributes(attributes, materials, images)
        feature_list.set_materials(materials)

        bt_attributes = content.body.batch_table.header.data
        [feature.set_batchtable_data(bt_attributes) for feature in feature_list]

        return feature_list
