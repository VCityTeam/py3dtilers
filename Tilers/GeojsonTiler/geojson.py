# -*- coding: utf-8 -*-
import sys
import numpy as np
import pywavefront
import geojson
from py3dtiles import BoundingVolumeBox, TriangleSoup
from Tilers.object_to_tile import ObjectToTile, ObjectsToTile

import os
from os import listdir
from os.path import isfile, join


# Todo : Comment
class Geojson(ObjectToTile):
    def __init__(self, id = None):
        super().__init__(id)

        self.geom = TriangleSoup()

    def get_geom_as_triangles(self):
        return self.geom.triangles[0]

    def set_triangles(self,triangles):
        self.geom.triangles[0] = triangles

    def parse_geom(self,path):
        # Realize the geometry conversion from geojson to GLTF
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

        triangles = list()
        for mesh in geom.mesh_list: 
            for face in mesh.faces:
                triangle = []
                for i in range(0,3): 
                    # We store each position for each triangles, as GLTF expect
                    triangle.append(np.array(geom.vertices[face[i]],
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

    def get_geojson_id(self):
        return super().get_id()
    
    def set_geojson_id(self,id):
        return super().set_id(id)

class Geojsons(ObjectsToTile):
    """
        A decorated list of ObjectsToTile type objects.
    """
    def __init__(self,objs=None):
        super().__init__(objs)

    def translate_tileset(self,offset):
        """
        :param objects: an array containing geojsons 
        :param offset: an offset
        :return: 
        """
        # Translate the position of each geojson by an offset
        for geojson in self.objects:
            new_geom = []
            for triangle in geojson.get_geom_as_triangles():
                new_position = []
                for points in triangle:
                    # Must to do this this way to ensure that the new position 
                    # stays in float32, which is mandatory for writing the GLTF
                    new_position.append(np.array(points - offset, dtype=np.float32))
                new_geom.append(new_position)
            geojson.set_triangles(new_geom)
            geojson.set_box() 
    
    @staticmethod
    def retrieve_geojsons(path, objects=list()):
        """
        :param path: a path to a directory

        :return: a list of geojson. 
        """

        geojson_dir = listdir(path)

        for geojson_file in geojson_dir:
            if(os.path.isfile(os.path.join(path,geojson_file))):
                if(".geojson" in geojson_file):
                    #Get id from its name
                    id = geojson_file.replace('.geojson','')
                    geojson = geojson(id)
                    #Create geometry as expected from GLTF from an geojson file
                    if(geojson.parse_geom(os.path.join(path,geojson_file))):
                        objects.append(geojson)
        
        return Geojsons(objects)    
