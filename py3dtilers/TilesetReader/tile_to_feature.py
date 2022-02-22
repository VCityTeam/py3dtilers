import os

from py3dtiles import TriangleSoup, GlTFMaterial
from ..Common import FeatureList, Feature
from ..Texture import Texture


class TileToFeature(Feature):

    def __init__(self, id=None, triangle_soup=None, mat_index=0):
        super().__init__(id)

        self.geom = triangle_soup
        self.set_box()

    def set_material(self, mat_index, materials, tileset_path=None):
        """
        Set the material of this geometry.
        :param mat_index: the index of the material
        :param materials: the list of all the materials
        :param tileset_path: the path to the tileset containing the texture image
        """
        self.material_index = mat_index
        if materials[mat_index].is_textured():
            path = os.path.join(tileset_path, "tiles", materials[mat_index].textureUri)
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

    def __find_materials(self, gltf):
        """
        Find the materials in the glTF and create GlTFMaterials.
        :param gltf: the gltf of the tile

        :return: a list of GlTFMaterials
        """
        materials = gltf.header['materials']
        gltf_materials = list()
        self.mat_offset = len(self.materials)
        for material in materials:
            pbr = material['pbrMetallicRoughness']
            rgba = pbr['baseColorFactor'] if 'baseColorFactor' in pbr else [1, 1, 1, 1]
            metallic_factor = pbr['metallicFactor'] if 'metallicFactor' in pbr else 1
            roughness_factor = pbr['roughnessFactor'] if 'roughnessFactor' in pbr else 1
            if 'baseColorTexture' in pbr:
                index = pbr['baseColorTexture']['index'] if 'index' in pbr['baseColorTexture'] else 0
                uri = gltf.header['images'][gltf.header['textures'][index]['source']]['uri']
            else:
                uri = None
            gltf_materials.append(GlTFMaterial(metallic_factor, roughness_factor, rgba, textureUri=uri))
        return gltf_materials

    def __convert_triangle_soup(self, triangle_soup, materials):
        """
        Convert the triangle soup to re-create the features.
        :param triangle_soup: the triangle soup
        :param materials: the materials of the tile

        :return: a FeatureList instance
        """
        triangles = triangle_soup.triangles[0]
        vertex_ids = triangle_soup.triangles[1]
        mat_indexes = triangle_soup.triangles[2]
        uvs = [] if len(triangle_soup.triangles) <= 3 else triangle_soup.triangles[3]

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

            triangle_dict[id].triangles[0].append(triangle)
            if uvs:
                triangle_dict[id].triangles[1].append(uvs[index])

        objects = []
        for id in triangle_dict:
            feature = TileToFeature(str(int(id)), triangle_dict[id], material_dict[id])
            feature.set_material(material_dict[id], materials, self.tileset_path)
            objects.append(feature)
        return FeatureList(objects)

    def __convert_tile(self, tile):
        """
        Convert a tile to a FeatureList instance.
        :param tile: the tile to convert

        :return: a FeatureList
        """
        gltf = tile.get_content().body.glTF

        materials = self.__find_materials(gltf)
        ts = TriangleSoup.from_glTF(gltf)
        feature_list = self.__convert_triangle_soup(ts, materials)
        feature_list.add_materials(materials)

        bt_attributes = tile.get_content().body.batch_table.attributes
        [feature.set_batchtable_data(bt_attributes) for feature in feature_list]

        return feature_list
