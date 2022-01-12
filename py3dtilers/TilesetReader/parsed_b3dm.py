import numpy as np

from py3dtiles import TriangleSoup, GlTFMaterial
from ..Common import ObjectsToTile, ObjectToTile


class ParsedB3dm(ObjectToTile):

    def __init__(self, id=None, triangle_soup=None, mat_index=0):
        super().__init__(id)

        self.geom = triangle_soup
        self.set_box()
        self.material_index = mat_index


class ParsedB3dms(ObjectsToTile):

    def __init__(self, objects=None):
        super().__init__(objects)
        self.materials = []
        self.mat_offset = 0

    def parse_materials(self, gltf):
        materials = gltf.header['materials']
        gltf_materials = list()
        self.mat_offset = len(self.materials)
        for material in materials:
            rgba = material['pbrMetallicRoughness']['baseColorFactor']
            metallic_factor = material['pbrMetallicRoughness']['metallicFactor']
            roughness_factor = material['pbrMetallicRoughness']['roughnessFactor']
            gltf_materials.append(GlTFMaterial(metallic_factor, roughness_factor, rgba))
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

        objects = [ParsedB3dm(str(id), triangle_dict[id], material_dict[id]) for id in triangle_dict]
        return ParsedB3dms(objects)

    def parse_tileset(self, tileset):
        all_tiles = tileset.get_root_tile().get_children()
        objects = list()
        for tile in all_tiles:
            gltf = tile.get_content().body.glTF
            self.parse_materials(gltf)
            ts = TriangleSoup.from_glTF(gltf)
            objects_to_tile = self.parse_triangle_soup(ts)
            centroid = np.array(tile.get_transform()[12:15], dtype=np.float32) * -1
            objects_to_tile.translate_objects(centroid)
            objects.append(objects_to_tile)
        return objects
