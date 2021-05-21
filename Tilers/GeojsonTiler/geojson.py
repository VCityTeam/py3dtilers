# -*- coding: utf-8 -*-
import sys
import numpy as np
import json
from py3dtiles import BoundingVolumeBox, TriangleSoup
from Tilers.object_to_tile import ObjectToTile, ObjectsToTile
from scipy.spatial import ConvexHull

import os
from os import listdir
from os.path import isfile, join


# The GeoJson file contains the ground surface of urban elements, mainly buildings.
# Those elements are called "features", each feature has its own ground coordinates.
# The goal here is to take those coordinates and create a box from it.
# To do this, we compute the center of the lower face
# Then we create the triangles of this face
# and duplicate it with a Z offset to create the upper face
# Then we create the side triangles to connect the upper and the lower faces
#                 Top
#                 .
#             .       .
#                 .


#     .           .
# .       .   .       .
#     .           .
#   Bottom      Bottom
class Geojson(ObjectToTile):

    n_feature = 0
    defaultZ = 144.

    def __init__(self, id = None):
        super().__init__(id)

        self.geom = TriangleSoup()

        self.z_max = 0

        self.vertices = list()
        self.triangles = list()

    def get_geom_as_triangles(self):
        return self.geom.triangles[0]

    def set_triangles(self,triangles):
        self.geom.triangles[0] = triangles
    
    def get_center(self,coords,height):
        x = 0
        y = 0
        z = 0
        
        for i in range(0,len(coords),3):
            x += coords[i]
            y += coords[i + 1]
            #z += coords[i + 2] - height
            z += self.z_max

        x /= len(coords) / 3
        y /= len(coords) / 3
        z /= len(coords) / 3

        return [x, y, z] 

    def create_triangles(self,vertices,coordsLenght):
        # Contains the triangles vertices. Used to create 3D tiles
        triangles = np.ndarray(shape=(coordsLenght * 4, 3, 3))

        # Contains the triangles vertices index. Used to create Objs
        triangles_id = np.ndarray(shape=(coordsLenght * 4, 3))
        k = 0

        # Triangles in lower and upper faces
        for j in range(1,coordsLenght + 1):
            # Lower
            triangles[k] = [vertices[0], vertices[j], vertices[(j % coordsLenght) + 1]]
            triangles_id[k] = [0, j, (j % coordsLenght) + 1]

            # Upper
            triangles[k + 1] = [vertices[(coordsLenght + 1)], vertices[(coordsLenght + 1) + (j % coordsLenght) + 1], vertices[(coordsLenght + 1) + j]]
            triangles_id[k + 1] = [(coordsLenght + 1), (coordsLenght + 1) + (j % coordsLenght) + 1, (coordsLenght + 1) + j]

            k += 2

        # Triangles sides
        for i in range(1,coordsLenght + 1):
            triangles[k] = [vertices[i], vertices[(coordsLenght + 1) + i], vertices[(coordsLenght + 1) + (i % coordsLenght) + 1]]
            triangles_id[k] = [i, (coordsLenght + 1) + i, (coordsLenght + 1) + (i % coordsLenght) + 1]

            triangles[k + 1] = [vertices[i], vertices[(coordsLenght + 1) + (i % coordsLenght) + 1], vertices[(i % coordsLenght) + 1]]
            triangles_id[k + 1] = [i, (coordsLenght + 1) + (i % coordsLenght) + 1,(i % coordsLenght) + 1]

            k += 2

        return [triangles,triangles_id]

    # Flatten list of lists (ex: [[a, b, c], [d, e, f], g]) to create a list (ex: [a, b, c, d, e, f, g])
    def flatten_list(self,list_of_lists):
        if len(list_of_lists) == 0:
            return list_of_lists
        if isinstance(list_of_lists[0], list):
            return self.flatten_list(list_of_lists[0]) + self.flatten_list(list_of_lists[1:])
        return list_of_lists[:1] + self.flatten_list(list_of_lists[1:])

    def skip_coord(self, coords):
        clean_coords = list()

        last_coord = [coords[0],coords[1],coords[2]]
        clean_coords.append(coords[0])
        clean_coords.append(coords[1])
        clean_coords.append(coords[2])

        for i in range(3,len(coords),3):
            coord = [coords[i],coords[i+1],coords[i+2]]
            diff_x = abs(last_coord[0] - coord[0])
            diff_y = abs(last_coord[1] - coord[1])
            if diff_x > 5 or diff_y > 5:
                clean_coords.append(coord[0])
                clean_coords.append(coord[1])
                clean_coords.append(coord[2])
                last_coord = coord

        return clean_coords

    def parse_geom(self,feature):
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

        # Current feature number
        Geojson.n_feature += 1

        coordinates = feature['geometry']['coordinates']

        try:
            coords = self.flatten_list(coordinates)
            # print(coords)
            # The last point in features is always the same as the first, so we remove the last point
            coords = coords[:len(coords)-3]
        except RecursionError:
            return False

        # coords = [coords[n:n+3] for n in range(0, len(coords), 3)]
        # hull = ConvexHull(coords)
        # print(hull)
        
        #coords = self.skip_coord(coords)
        #coords = self.flatten_list(coords)
        coordsLenght = len(coords) // 3

        vertices = np.ndarray(shape=(2 * (coordsLenght + 1), 3))

        self.z_max = Geojson.defaultZ
        height = 0

        # If PREC_ALTI is equal to 9999, it means Z values of the features are missing, so we skip the feature
        if "PREC_ALTI" in feature['properties']:
            if feature['properties']['PREC_ALTI'] >= 9999.:
                return False
        else:
            print("No propertie called PREC_ALTI in feature " + str(Geojson.n_feature))
            return False

        if "HAUTEUR" in feature['properties']:
            if feature['properties']['HAUTEUR'] > 0:
                height = feature['properties']['HAUTEUR']
            else:
                return False
        else:
            print("No propertie called HAUTEUR in feature " + str(Geojson.n_feature))
            return False

        if "Z_MAX" in feature['properties']:
            if feature['properties']['Z_MAX'] > 0:
                self.z_max = feature['properties']['Z_MAX'] - height
        else:
            print("No propertie called Z_MAX in feature " + str(Geojson.n_feature))
            return False

        # Set bottom center vertice value
        vertices[0] = self.get_center(coords,height)
        # Set top center vertice value
        vertices[coordsLenght + 1] = [vertices[0][0], vertices[0][1], vertices[0][2] + height]

        # For each coordinates, add a vertice at the coordinates and a vertice at the same coordinates with a Y-offset
        for i in range(0, coordsLenght):
            # z = coords[(i * 3) + 2] - height
            z = self.z_max

            vertices[i + 1] = [coords[i * 3], coords[(i * 3) + 1], z]
            vertices[i + coordsLenght + 2] = [coords[i * 3], coords[(i * 3) + 1], z + height]

        if(len(vertices)==0):
            return False

        triangles = self.create_triangles(vertices,coordsLenght)

        self.geom.triangles.append(triangles[0])

        self.set_box()

        self.vertices = vertices
        self.triangles = triangles[1]

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

        vertices = list()
        triangles = list()
        vertice_offset = 1

        for geojson_file in geojson_dir:
            if(os.path.isfile(os.path.join(path,geojson_file))):
                if(".geojson" in geojson_file or ".json" in geojson_file):
                    #Get id from its name
                    id = geojson_file.replace('json','')
                    with open(os.path.join(path,geojson_file)) as f:
                        gjContent = json.load(f)

                    k = 0
                    for feature in gjContent['features']:

                        if "ID" in feature['properties']:
                            feature_id = feature['properties']['ID']
                        else:
                            feature_id = id + str(k)
                            k += 1
                        geojson = Geojson(feature_id)
                        #Create geometry as expected from GLTF from an geojson file
                        if(geojson.parse_geom(feature)):
                            objects.append(geojson)
                            for vertice in geojson.vertices:
                                vertices.append(vertice)
                            for triangle in geojson.triangles:
                                triangles.append(triangle + vertice_offset)
                            vertice_offset += len(geojson.vertices)
        
        print("Warning: Writting features as Objs might take a long time")
        file_name = "result.obj"
        f = open(os.path.join("debugObjs",file_name), "w")
        f.write("# " + file_name + "\n")
        
        for vertice in vertices:
            f.write("v "+str(vertice[0]-1840000)+" "+str(vertice[1]-5170000)+" "+str(vertice[2])+"\n")

        for triangle in triangles:
            f.write("f "+str(int(triangle[0]))+" "+str(int(triangle[1]))+" "+str(int(triangle[2]))+"\n")
        
        return Geojsons(objects)    
