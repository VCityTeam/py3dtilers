# -*- coding: utf-8 -*-
import os
from os import listdir

import numpy as np
import pywavefront

from ..Common import ObjectToTile, ObjectsToTile
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
class Obj(ObjectToTile):
    def __init__(self, id=None):
        super().__init__(id)

    def parse_geom(self, mesh):
        """
        Parse the geometry of a OBJ mesh to create a triangle soup with UVs.
        :param mesh: an OBJ mesh

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

        vertices = mesh.materials[0].vertices
        length = len(vertices)
        # Contains only vertex positions
        if mesh.materials[0].vertex_format == 'V3F':
            for i in range(0, length, 9):
                triangle = [np.array(vertices[n:n + 3], dtype=np.float32) for n in range(i, i + 9, 3)]
                triangles.append(triangle)
        # Contains texture and vertex positions
        elif mesh.materials[0].vertex_format == 'T2F_V3F':
            for i in range(0, length, 15):
                triangle = [np.array(vertices[n:n + 3], dtype=np.float32) for n in range(i + 2, i + 17, 5)]
                triangles.append(triangle)
                uv = [np.array([vertices[n], 1 - vertices[n + 1]], dtype=np.float32) for n in range(i, i + 15, 5)]
                uvs.append(uv)
        # Contains texture/vertex positions and normals
        elif mesh.materials[0].vertex_format == 'T2F_N3F_V3F':
            for i in range(0, length, 24):
                triangle = [np.array(vertices[n:n + 3], dtype=np.float32) for n in range(i + 5, i + 29, 8)]
                triangles.append(triangle)
                uv = [np.array([vertices[n], 1 - vertices[n + 1]], dtype=np.float32) for n in range(i, i + 24, 8)]
                uvs.append(uv)
        else:
            return False

        self.geom.triangles.append(triangles)
        if len(uvs) > 0:
            self.geom.triangles.append(uvs)
            if mesh.materials[0].texture is not None:
                path = str(mesh.materials[0].texture._path).replace('\\', '/')
                texture = Texture(path)
                self.set_texture(texture.get_cropped_texture_image(self.geom.triangles[1]))
        self.set_box()

        return True

    def get_obj_id(self):
        return super().get_id()

    def set_obj_id(self, id):
        return super().set_id(id)


class Objs(ObjectsToTile):
    """
        A decorated list of ObjectsToTile type objects.
    """

    def __init__(self, objs=None):
        super().__init__(objs)

    @staticmethod
    def retrieve_objs(path):
        """
        Create Obj instance from OBJ file(s).
        :param path: a path to a directory

        :return: a list of Obj.
        """
        objects = list()
        obj_dir = listdir(path)

        for obj_file in obj_dir:
            if(os.path.isfile(os.path.join(path, obj_file))):
                if(".obj" in obj_file):
                    geom = pywavefront.Wavefront(os.path.join(path, obj_file), collect_faces=True)
                    if(len(geom.vertices) == 0):
                        continue
                    for mesh in geom.mesh_list:
                        # Get id from its name
                        id = mesh.name
                        obj = Obj(id)
                        # Create geometry as expected from GLTF from an obj file
                        if(obj.parse_geom(mesh)):
                            objects.append(obj)

        return Objs(objects)
