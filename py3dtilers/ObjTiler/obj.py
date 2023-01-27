# -*- coding: utf-8 -*-
import numpy as np
import pywavefront
from py3dtiles import GlTFMaterial

from ..Common import Feature, FeatureList
from ..Texture import Texture


# This Obj class refers to the obj file fromat (https://en.wikipedia.org/wiki/Wavefront_.obj_file)
# It is a 3D object file format that describes the object in the following way :
# The position of each Vertex, then the face, using the index of each Vertex.
# Example :
# v 0.0 0.0 0.0
# v 0.5 0.5 0.5
# v 1.0 1.0 1.0
# v -1.0 -1.0 -1.0
#
# f 1 2 3
# f 2 3 4
class Obj(Feature):
    """
    The Python representation of an OBJ mesh.
    """

    def __init__(self, id=None):
        super().__init__(id)

    def set_material_index(self, index):
        self.material_index = index

    def parse_geom(self, material, with_texture=False):
        """
        Parse the geometry of a OBJ mesh to create a triangle soup with UVs.
        :param mesh: an OBJ mesh
        :param with_texture: a boolean indicating if the textures should be read

        :return: True if the parsing is complete, False if the format wasn't supported
        """
        # Realize the geometry conversion from OBJ to GLTF
        # GLTF expect the geometry to only be triangles that contains
        # the vertices position, i.e something in the form :
        # [
        #   [np.array([0., 0., 0,]),
        #    np.array([0.5, 0.5, 0.5]),
        #    np.array([1.0 ,1.0 ,1.0])]
        #   [np.array([0.5, 0.5, 0,5]),
        #    np.array([1., 1., 1.]),
        #    np.array([-1.0 ,-1.0 ,-1.0])]
        # ]
        triangles = list()
        uvs = list()

        vertices = material.vertices
        length = len(vertices)
        vertex_format = material.vertex_format
        # Contains only vertex positions
        if vertex_format == 'V3F':
            for i in range(0, length, 9):
                triangle = [np.array(vertices[n:n + 3]) for n in range(i, i + 9, 3)]
                triangles.append(triangle)
        # Contains normals and vertex positions
        elif vertex_format == 'N3F_V3F':
            for i in range(0, length, 18):
                triangle = [np.array(vertices[n:n + 3]) for n in range(i + 3, i + 21, 6)]
                triangles.append(triangle)
        # Contains texture and vertex positions
        elif vertex_format == 'T2F_V3F':
            for i in range(0, length, 15):
                triangle = [np.array(vertices[n:n + 3]) for n in range(i + 2, i + 17, 5)]
                triangles.append(triangle)
                uv = [np.array([vertices[n], 1 - vertices[n + 1]]) for n in range(i, i + 15, 5)]
                uvs.append(uv)
        # Contains texture/vertex positions and normals
        elif vertex_format == 'T2F_N3F_V3F' or vertex_format == 'T2F_C3F_V3F':
            for i in range(0, length, 24):
                triangle = [np.array(vertices[n:n + 3]) for n in range(i + 5, i + 29, 8)]
                triangles.append(triangle)
                uv = [np.array([vertices[n], 1 - vertices[n + 1]]) for n in range(i, i + 24, 8)]
                uvs.append(uv)
        elif vertex_format == 'T2F_C3F_N3F_V3F':
            for i in range(0, length, 33):
                triangle = [np.array(vertices[n:n + 3]) for n in range(i + 8, i + 41, 11)]
                triangles.append(triangle)
                uv = [np.array([vertices[n], 1 - vertices[n + 1]]) for n in range(i, i + 33, 11)]
                uvs.append(uv)
        else:
            print("Unsuported format", vertex_format)
            return False

        self.geom.triangles.append(triangles)
        if len(uvs) > 0 and with_texture:
            self.geom.triangles.append(uvs)
            if material.texture is not None:
                path = str(material.texture._path).replace('\\', '/')
                texture = Texture(path)
                self.set_texture(texture.get_cropped_texture_image(self.geom.triangles[1]))
        self.set_box()

        return True


class Objs(FeatureList):
    """
        A decorated list of FeatureList type objects.
    """

    def __init__(self, objs=None):
        super().__init__(objs)

    @staticmethod
    def retrieve_objs(files, with_texture=False):
        """
        Create Obj instance from OBJ file(s).
        :param files: paths to files
        :param with_texture: a boolean indicating if the textures should be read
        :return: a list of Obj.
        """
        objects = list()

        for obj_file in files:
            print("Reading " + str(obj_file))
            geom = pywavefront.Wavefront(obj_file, collect_faces=True, create_materials=True)
            mesh = geom.mesh_list[0]
            if len(geom.vertices) == 0:
                continue
            gltfMaterials = []
            mesh_index = 1

            for mesh in mesh.materials:
                # get id from its name
                id = mesh.name
                obj = Obj(id)
                obj.set_material_index(mesh_index)
                mesh_index += 1
                if obj.parse_geom(mesh, with_texture):                        
                    objects.append(obj)
                material = GlTFMaterial(rgb=[mesh.diffuse[0], mesh.diffuse[1], mesh.diffuse[2]], alpha=1. - mesh.diffuse[3], metallicFactor=0.)
                gltfMaterials.append(material)

        fList = Objs(objects)
        fList.add_materials(gltfMaterials)

        return fList
