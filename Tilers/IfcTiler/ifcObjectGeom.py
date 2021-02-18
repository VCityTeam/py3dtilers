# -*- coding: utf-8 -*-
import sys
import numpy as np
import pywavefront
from py3dtiles import BoundingVolumeBox, TriangleSoup
from Tilers.object_to_tile import ObjectToTile, ObjectsToTile

import os
from os import listdir
from os.path import isfile, join

class IfcObjectGeom(ObjectToTile):
    def __init__(self, id = None):
        super().__init__(id)

        self.geom = TriangleSoup()

    def get_geom_as_triangles(self):
        return self.geom.triangles[0]

    def set_triangles(self,triangles):
        self.geom.triangles[0] = triangles

    def parse_geom(self,bimserver):
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

        # getoidbyguid(id)
        # faces = bimserver.getFaces ...
        # vertices = bimserver.getFaces ...
        triangles = list()
        for face in faces:
            triangle = []
            for i in range(0,3): 
                # We store each position for each triangles, as GLTF expect
                triangle.append(np.array(vertices[face[i]],
                    dtype=np.float64))
            triangles.append(triangle)
        self.geom.triangles.append(triangles)

        self.set_box()

        return True
    
    def set_box(self):
        """
        Parameters
        ----------
        Returns
        -------
        """
        bbox = self.geom.getBbox()
        self.box = BoundingVolumeBox()
        self.box.set_from_mins_maxs(np.append(bbox[0],bbox[1]))
        
        # Set centroid from Bbox center
        self.centroid = np.array([(bbox[0][0] + bbox[1][0]) / 2.0,
                         (bbox[0][1] + bbox[1][1]) / 2.0,
                         (bbox[0][2] + bbox[0][2]) / 2.0])

    def get_obj_id(self):
        return super().get_id()
    
    def set_obj_id(self,id):
        return super().set_id(id)

class IfcObjectsGeom(ObjectsToTile):
    """
        A decorated list of ObjectsToTile type objects.
    """
    def __init__(self,objs=None):
        super().__init__(objs)

    def translate_tileset(self,offset):
        """
        :param objects: an array containing objs 
        :param offset: an offset
        :return: 
        """
        # Translate the position of each obj by an offset
        for obj in self.objects:
            new_geom = []
            for triangle in obj.get_geom_as_triangles():
                new_position = []
                for points in triangle:
                    # Must to do this this way to ensure that the new position 
                    # stays in float32, which is mandatory for writing the GLTF
                    new_position.append(np.array(points - offset, dtype=np.float32))
                new_geom.append(new_position)
            obj.set_triangles(new_geom)
            obj.set_box() 
    
    @staticmethod
    def retrieve_IfcObjs(bimserver,oidList,objects=list()):
        """
        :param path: a path to a directory

        :return: a list of Obj. 
        """

        for oid in oidList:
                    #Get guid from its name
                    guid = 0 
                    obj = IfcObjectGeom(guid)
                    # #Create geometry as expected from GLTF
                    obj.parse_geom(bimserver)
                    objects.append(obj)
        
        return IfcObjectsGeom(objects)    
