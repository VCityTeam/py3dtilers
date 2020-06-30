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
        self.id = id

    def get_id(self):
        return self.id

    def get_centroid(self):
        return self.centroid

    def get_bounding_volume_box(self):
        return self.box


    def parse_geom(self,path):
        
        geom = pywavefront.Wavefront(path, collect_faces = True)
        box_max = [None,None,None]
        box_min = [None,None,None]

        triangles = []

        for mesh in geom.mesh_list:    
            for face in mesh.faces:
                for i in range(0,3): #On récupère les 3 sommets indiqués par chaque face
                    triangles.append(np.array(geom.vertices[face[i]], dtype=np.float32))
                    for j in range(0,3): #On récupère la boite englobante de la géométrie
                        if(box_max[j] == None):
                            box_max[j] = geom.vertices[face[i]][j]
                            box_min[j] = geom.vertices[face[i]][j]
                        elif(box_min[j] > geom.vertices[face[i]][j]):
                            box_min[j] = geom.vertices[face[i]][j]
                        elif(box_max[j] < geom.vertices[face[i]][j]):
                            box_max[j] = geom.vertices[face[i]][j]
                           
        self.box = BoundingVolumeBox()
        self.box.set_from_mins_maxs([box_max[0],box_max[1],box_max[2],box_min[0],box_min[1],box_min[2]])

        self.centroid = [(box_max[0] + box_min[0]) / 2.0,
                         (box_max[1] + box_min[1]) / 2.0,
                         (box_max[2] + box_min[2]) / 2.0]
        self.geom.append(triangles)
             
         


        


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

