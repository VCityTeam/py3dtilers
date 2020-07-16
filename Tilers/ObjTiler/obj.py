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

        self.id = ifc_id 

    def set_id(self, id):
        self.id = id

    def get_id(self):
        return self.id

    def get_centroid(self):
        return self.centroid

    def get_bounding_volume_box(self):
        return self.box

    def get_geom(self):
        return self.geom

    def set_geom(self,geom):
        self.geom = geom

    def parse_geom(self,path):
        # Realize the geometry conversion from OBJ to GLTF
        # The geometry is described in an obj file by writting vertices position 
        # and writting triangles using vertex indices (https://en.wikipedia.org/wiki/Wavefront_.obj_file)
        # i.e something in the form :
        # v 0.0 0.0 0.0
        # v 0.5 0.5 0.5
        # v 1.0 1.0 1.0
        # v -1.0 -1.0 -1.0
        # 
        # f 1 2 3
        # f 2 3 4
        #  
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

        geom = pywavefront.Wavefront(path, collect_faces = True)
        if(len(geom.vertices)==0):
            return False

        for mesh in geom.mesh_list:    
            for face in mesh.faces:
                triangles = []
                for i in range(0,3): # We store each position for each triangles, as GLTF expect
                    triangles.append(np.array(geom.vertices[face[i]], dtype=np.float64))
                self.geom.append(triangles)

        self.set_bbox()

        return True
    
    def set_bbox(self):
        """
        Parameters
        ----------
        Returns
        -------
        """
        bbox = self.getBbox()
        self.box = BoundingVolumeBox()
        self.box.set_from_mins_maxs(np.append(bbox[0],bbox[1]))
        
        # Set centroid from Bbox center
        self.centroid = np.array([(bbox[0][0] + bbox[1][0]) / 2.0,
                         (bbox[0][1] + bbox[1][1]) / 2.0,
                         (bbox[0][2] + bbox[0][2]) / 2.0])

    def getPositionArray(self):
        """
        Parameters
        ----------
        Returns
        -------
        Binary array of vertice position
        """
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

