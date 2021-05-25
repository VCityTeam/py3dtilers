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
#
#
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
        self.height = 0
        self.center = []

        self.vertices = list()
        self.triangles = list()

        self.coords = list()

    def get_geom_as_triangles(self):
        return self.geom.triangles[0]

    def set_triangles(self,triangles):
        self.geom.triangles[0] = triangles
    
    def get_center(self,coords):
        x = 0
        y = 0
        
        for i in range(0,len(coords)):
            x += coords[i][0]
            y += coords[i][1]

        x /= len(coords)
        y /= len(coords)

        return [x, y, self.z_max] 

    def create_triangles(self,vertices,coordsLenght):
        # Contains the triangles vertices. Used to create 3D tiles
        triangles = np.ndarray(shape=(coordsLenght * 4, 3, 3))

        # Contains the triangles vertices index. Used to create Objs
        triangles_id = np.ndarray(shape=(coordsLenght * 4, 3))
        k = 0

        # Triangles in lower and upper faces
        for j in range(1,coordsLenght + 1):
            # Lower
            triangles[k] = [vertices[0], vertices[(j % coordsLenght) + 1], vertices[j]]
            triangles_id[k] = [0, (j % coordsLenght) + 1, j]

            # Upper
            triangles[k + 1] = [vertices[(coordsLenght + 1)], vertices[(coordsLenght + 1) + j], vertices[(coordsLenght + 1) + (j % coordsLenght) + 1]]
            triangles_id[k + 1] = [(coordsLenght + 1), (coordsLenght + 1) + j, (coordsLenght + 1) + (j % coordsLenght) + 1]

            k += 2

        # Triangles in side faces
        for i in range(1,coordsLenght + 1):
            triangles[k] = [vertices[i], vertices[(coordsLenght + 1) + (i % coordsLenght) + 1], vertices[(coordsLenght + 1) + i]]
            triangles_id[k] = [i, (coordsLenght + 1) + (i % coordsLenght) + 1, (coordsLenght + 1) + i]

            triangles[k + 1] = [vertices[i], vertices[(i % coordsLenght) + 1], vertices[(coordsLenght + 1) + (i % coordsLenght) + 1]]
            triangles_id[k + 1] = [i,(i % coordsLenght) + 1, (coordsLenght + 1) + (i % coordsLenght) + 1]

            k += 2

        return [triangles,triangles_id]


    # Flatten list of lists (ex: [[a, b, c], [d, e, f], g]) to create a list (ex: [a, b, c, d, e, f, g])
    def flatten_list(self,list_of_lists):
        if len(list_of_lists) == 0:
            return list_of_lists
        if isinstance(list_of_lists[0], list):
            return self.flatten_list(list_of_lists[0]) + self.flatten_list(list_of_lists[1:])
        return list_of_lists[:1] + self.flatten_list(list_of_lists[1:])

    def parse_geojson(self,feature,properties):
        # Current feature number
        Geojson.n_feature += 1

        # If precision is equal to 9999, it means Z values of the features are missing, so we skip the feature
        prec_name = properties[properties.index('prec') + 1]
        if  prec_name in feature['properties']:
            if feature['properties'][prec_name] >= 9999.:
                return False
        else:
            print("No propertie called " + prec_name + " in feature " + str(Geojson.n_feature))
            return False

        height_name = properties[properties.index('height') + 1]
        if  height_name in feature['properties']:
            if feature['properties'][height_name] > 0:
                self.height = feature['properties'][height_name]
            else:
                return False
        else:
            print("No propertie called " + height_name + " in feature " + str(Geojson.n_feature))
            return False

        z_name = properties[properties.index('z') + 1]
        if  z_name in feature['properties']:
            self.z_max = feature['properties'][z_name] - self.height
        else:
            print("No propertie called " + z_name + " in feature " + str(Geojson.n_feature))
            return False

        coordinates = feature['geometry']['coordinates']

        try:
            coords = self.flatten_list(coordinates)
            # Group coords into (x,y) arrays, the z will always be the z_max
            # The last point in features is always the same as the first, so we remove the last point
            coords = [coords[n:n+2] for n in range(0, len(coords)-3, 3)]
            self.coords = coords
            center = self.get_center(coords)
            self.center = [center[0], center[1], center[2] + self.height / 2]
        except RecursionError:
            return False

        return True

    def parse_geom(self):
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

        coords = self.coords
        height = self.height

        # If the feature has at least 4 coords, create a convex hull
        # The convex hull reduces the number of points and the level of detail
        if len(coords) >= 4:
            hull = ConvexHull(coords)
            coords = [coords[i] for i in hull.vertices]
        
        coordsLenght = len(coords)
        vertices = np.ndarray(shape=(2 * (coordsLenght + 1), 3))

        # Set bottom center vertice value
        vertices[0] = self.get_center(coords)
        # Set top center vertice value
        vertices[coordsLenght + 1] = [vertices[0][0], vertices[0][1], vertices[0][2] + height]

        # For each coordinates, add a vertice at the coordinates and a vertice above at the same coordinates but with a Z-offset
        for i in range(0, coordsLenght):
            z = self.z_max

            vertices[i + 1] = [coords[i][0], coords[i][1], z]
            vertices[i + coordsLenght + 2] = [coords[i][0], coords[i][1], z + height]

        if(len(vertices)==0):
            return False

        # triangles[0] contains the triangles with coordinates ([[x1, y1, z1], [x2, y2, z2], [x3, y3, z3]) used for 3DTiles
        # triangles[1] contains the triangles with indexes ([1, 2, 3]) used for Objs
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

    defaultGroupOffset = 50

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

    # Round the coordinate to the closest multiple of 'base'
    @staticmethod
    def round_coordinate(coordinate,base):
        rounded_coord = coordinate
        for i in range(0,len(coordinate)):
            rounded_coord[i] = base * round(coordinate[i]/base)
        return rounded_coord

    # Group features which are in the same cube of size 'size'
    @staticmethod
    def group_features_by_center(features,size):
        grouped_features = list()
        features_dict = {}
        
        # Create a dictionary key: cubes center (x,y,z); value: list of features index
        for i in range(0,len(features)):
            closest_cube = Geojsons.round_coordinate(features[i].center,size)
            if tuple(closest_cube) in features_dict:
                features_dict[tuple(closest_cube)].append(i)
            else:
                features_dict[tuple(closest_cube)] = [i]

        # For every cube, merge the features contained in this cube
        k = 0
        for cube in features_dict:
            geojson = Geojson("group"+str(k))
            z = 9999
            height = 0
            coords = list()

            for j in features_dict[cube]:
                if height < features[j].height:
                    height = features[j].height
                if z > features[j].z_max:
                    z = features[j].z_max
                for coord in features[j].coords:
                    coords.append(coord)

            center = geojson.get_center(coords)
            geojson.coords = coords
            geojson.z_max = z
            geojson.height = height
            geojson.center = [center[0], center[1], center[2] + geojson.height / 2]
            grouped_features.append(geojson)
            k += 1

        return grouped_features

    @staticmethod
    def retrieve_geojsons(path, lod, properties, objects=list()):
        """
        :param path: a path to a directory

        :return: a list of geojson. 
        """

        geojson_dir = listdir(path)

        vertices = list()
        triangles = list()
        geojsons = list()
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
                        if(geojson.parse_geojson(feature,properties)):
                            geojsons.append(geojson)

                    if 'group' in lod:
                        try:
                            size = int(lod[1])
                        except:
                            size = Geojsons.defaultGroupOffset
                        geojsons = Geojsons.group_features_by_center(geojsons,size)

                    for geojson in geojsons:
                        #Create geometry as expected from GLTF from an geojson file
                        if(geojson.parse_geom()):
                            objects.append(geojson)
                            # Add triangles and vertices to create an obj
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
