# -*- coding: utf-8 -*-
import sys
import numpy as np
import pywavefront
from py3dtiles import BoundingVolumeBox


class Obj(object):
    def __init__(self, ifc_id = None):

        self.geom = list()

        self.box = None

        self.centroid = None

        self.id = ifc_id if ifc_id else None   

    def set_id(self, id):
        self.database_id = id

    def get_id(self):
        return self.database_id

    def get_centroid(self):
        return self.centroid

    def get_bounding_volume_box(self):
        return self.box


    def parse_geom(self,geom):
        vertices = geom.vertices
        for mesh in geom.mesh_list:    
            for face in mesh.faces:
                triangle = []
                triangle.append(np.array(vertices[face[0]], dtype=np.float32))
                triangle.append(np.array(vertices[face[1]], dtype=np.float32))
                triangle.append(np.array(vertices[face[2]], dtype=np.float32))
                self.geom.append(triangle) 
        #create box and centroid        


    def getPositionArray(self):
        array = []
        for face in self.geom:
            for vertex in face:
                array.append(vertex)
        return b''.join(array)


    def getNormalArray(self):
        """
        Parameters
        ----------
        Returns
        -------
        Binary array of vertice normals
        """
        normals = []
        for t in self.geom:
            U = t[1] - t[0]
            V = t[2] - t[0]
            N = np.cross(U, V)
            norm = np.linalg.norm(N)
            if norm == 0:
                normals.append(np.array([0, 0, 1], dtype=np.float32))
            else:
                normals.append(N / norm)
        verticeArray = faceAttributeToArray(normals)
        return b''.join(verticeArray)


   
    def getBbox(self):
        """
        Parameters
        ---------
        Returns
        -------
        Array [[minX, minY, minZ],[maxX, maxY, maxZ]]
        """
        mins = np.array([np.min(t, 0) for t in self.geom])
        maxs = np.array([np.max(t, 0) for t in self.geom])
        return [np.min(mins, 0), np.max(maxs, 0)]


def faceAttributeToArray(triangles):
    array = []
    for face in triangles:
        array += [face, face, face]
    return array
