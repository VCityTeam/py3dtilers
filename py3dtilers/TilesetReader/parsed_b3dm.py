import numpy as np
import os

from py3dtiles import TriangleSoup, GlTFMaterial
from ..Common import ObjectsToTile, ObjectToTile
from ..Texture import Texture


class ParsedB3dm(ObjectToTile):

    def __init__(self, id=None, triangle_soup=None, mat_index=0):
        super().__init__(id)

        self.geom = triangle_soup
        self.set_box()

    def set_material(self, mat_index, materials, tileset_path=None):
        self.material_index = mat_index
        if materials[mat_index].is_textured():
            path = os.path.join(tileset_path, "tiles", materials[mat_index].textureUri)
            texture = Texture(path, self.geom.triangles[1])
            self.set_texture(texture.get_texture_image())

    def set_batchtable_data(self, bt_attributes):
        data = {}
        for attribute in bt_attributes:
            if attribute == 'ids':
                self.set_id(bt_attributes[attribute][int(self.id)])
            else:
                data[attribute] = bt_attributes[attribute][int(self.id)]
        if data:
            super().set_batchtable_data(data)


class ParsedB3dms(ObjectsToTile):

    def __init__(self, objects=None, tileset_path=None):
        super().__init__(objects)
        self.materials = []
        self.mat_offset = 0
        self.tileset_path = tileset_path

    def parse_materials(self, gltf):
        materials = gltf.header['materials']
        gltf_materials = list()
        self.mat_offset = len(self.materials)
        for material in materials:
            rgba = material['pbrMetallicRoughness']['baseColorFactor']
            metallic_factor = material['pbrMetallicRoughness']['metallicFactor']
            roughness_factor = material['pbrMetallicRoughness']['roughnessFactor']
            if 'baseColorTexture' in material['pbrMetallicRoughness']:
                index = material['pbrMetallicRoughness']['baseColorTexture']['index']
                uri = gltf.header['images'][gltf.header['textures'][index]['source']]['uri']
            else:
                uri = None
            gltf_materials.append(GlTFMaterial(metallic_factor, roughness_factor, rgba, textureUri=uri))
        self.add_materials(gltf_materials)

    def parse_triangle_soup(self, triangle_soup):
        triangles = triangle_soup.triangles[0]
        vertex_ids = triangle_soup.triangles[1]
        mat_indexes = triangle_soup.triangles[2]
        uvs = [] if len(triangle_soup.triangles) <= 3 else triangle_soup.triangles[3]

        triangle_dict = dict()
        material_dict = dict()
        for index, triangle in enumerate(triangles):
            id = vertex_ids[3 * index][0]

            if id not in triangle_dict:
                mat_index = int(mat_indexes[int(vertex_ids[3 * index][1])]) + self.mat_offset
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
            feature = ParsedB3dm(str(int(id)), triangle_dict[id], material_dict[id])
            feature.set_material(material_dict[id], self.materials, self.tileset_path)
            objects.append(feature)
        return ParsedB3dms(objects)

    def parse_tileset(self, tileset):
        all_tiles = tileset.get_root_tile().get_children()
        objects = list()
        for tile in all_tiles:
            gltf = tile.get_content().body.glTF

            self.parse_materials(gltf)
            ts = TriangleSoup.from_glTF(gltf)
            objects_to_tile = self.parse_triangle_soup(ts)

            bt_attributes = tile.get_content().body.batch_table.attributes
            [feature.set_batchtable_data(bt_attributes) for feature in objects_to_tile]

            centroid = np.array(tile.get_transform()[12:15], dtype=np.float32) * -1
            objects_to_tile.translate_objects(centroid)

            objects.append(objects_to_tile)
        return objects
