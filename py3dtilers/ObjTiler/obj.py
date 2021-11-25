# -*- coding: utf-8 -*-
import os
from os import listdir

import numpy as np
import pywavefront

from ..Common import ObjectToTile, ObjectsToTile


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

    def parse_geom(self, path):
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

        geom = pywavefront.Wavefront(path, collect_faces=True)
        if(len(geom.vertices) == 0):
            return False

        triangles = list()
        for mesh in geom.mesh_list:
            for face in mesh.faces:
                triangle = []
                for i in range(0, 3):
                    # We store each position for each triangles, as GLTF expect
                    triangle.append(np.array(geom.vertices[face[i]],
                                             dtype=np.float64))
                triangles.append(triangle)
        self.geom.triangles.append(triangles)

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
    def retrieve_objs(path, objects=list()):
        """
        :param path: a path to a directory

        :return: a list of Obj.
        """

        obj_dir = listdir(path)

        for obj_file in obj_dir:
            if(os.path.isfile(os.path.join(path, obj_file))):
                if(".obj" in obj_file):
                    # Get id from its name
                    id = obj_file.replace('.obj', '')
                    obj = Obj(id)
                    # Create geometry as expected from GLTF from an obj file
                    if(obj.parse_geom(os.path.join(path, obj_file))):
                        objects.append(obj)

        return Objs(objects)
