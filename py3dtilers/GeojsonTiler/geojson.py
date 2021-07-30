# -*- coding: utf-8 -*-
import os
from os import listdir
import numpy as np
import json
import tripy

from ..Common import ObjectToTile, ObjectsToTile


# The GeoJson file contains the ground surface of urban elements, mainly buildings.
# Those elements are called "features", each feature has its own ground coordinates.
# The goal here is to take those coordinates and create a box from it.
# To do this, we compute the center of the lower face
# Then we create the triangles of this face
# and duplicate it with a Z offset to create the upper face
# Then we create the side triangles to connect the upper and the lower faces
class Geojson(ObjectToTile):

    n_feature = 0

    def __init__(self, id=None):
        super().__init__(id)

        self.z = 0
        """Altitude of the polygon that will be extruded to create the 3D geometry"""

        self.height = 0
        """How high we extrude the polygon when creating the 3D geometry"""

        self.center = []

        self.vertices = list()
        self.triangles = list()

        self.coords = list()

    def find_coordinate_index(self, coordinates, value):
        for i, coord in enumerate(coordinates):
            if coord[0] == value[0]:
                if coord[1] == value[1]:
                    return i
        return None

    def get_center(self, coords):
        length = len(coords)
        sum_x = np.sum([coord[0] for coord in coords])
        sum_y = np.sum([coord[1] for coord in coords])
        return np.array([sum_x / length, sum_y / length, self.z], dtype=np.float32)

    def parse_geojson(self, feature, properties, is_roof):
        """
        Parse a feature of the .geojson file to extract the height and the coordinates of the feature.
        """
        # Current feature number (used for debug)
        Geojson.n_feature += 1

        # If precision is equal to 9999, it means Z values of the features are missing, so we skip the feature
        prec_name = properties[properties.index('prec') + 1]
        if prec_name != 'NONE':
            if prec_name in feature['properties']:
                if feature['properties'][prec_name] >= 9999.:
                    return False
            else:
                print("No propertie called " + prec_name + " in feature " + str(Geojson.n_feature))
                return False

        height_name = properties[properties.index('height') + 1]
        if height_name in feature['properties']:
            if feature['properties'][height_name] > 0:
                self.height = feature['properties'][height_name]
            else:
                return False
        else:
            print("No propertie called " + height_name + " in feature " + str(Geojson.n_feature))
            self.height = 5

        if feature['geometry']['type'] == 'Polygon':
            coords = feature['geometry']['coordinates'][0]
        if feature['geometry']['type'] == 'MultiPolygon':
            coords = feature['geometry']['coordinates'][0][0]

        self.z = min(coords, key=lambda x: x[2])[2]
        if is_roof:
            self.z -= self.height

        # Group coords into (x,y) arrays, the z will always be the same z
        # The last point in features is always the same as the first, so we remove the last point
        coords = [(coords[n][0], coords[n][1]) for n in range(0, len(coords) - 1)]
        self.coords = coords
        center = self.get_center(coords)
        self.center = [center[0], center[1], center[2] + self.height / 2]

        return True

    def parse_geom(self, create_obj=False):
        """
        Creates the 3D extrusion of the feature.
        """
        coordinates = self.coords
        length = len(coordinates)
        vertices = [None] * (2 * length)
        z = self.z
        height = self.height

        for i, coord in enumerate(coordinates):
            vertices[i] = np.array([coord[0], coord[1], z], dtype=np.float32)
            vertices[i + length] = np.array([coord[0], coord[1], z + height], dtype=np.float32)

        # Contains the triangles vertices. Used to create 3D tiles
        triangles = list()
        # Contains the triangles vertices index. Used to create Objs
        triangles_id = list()

        # Triangulate the feature footprint
        poly_triangles = tripy.earclip(coordinates)

        # Create lower and upper faces triangles
        for tri in poly_triangles:
            lower_tri = [np.array([coord[0], coord[1], z], dtype=np.float32) for coord in reversed(tri)]
            triangles.append(lower_tri)
            upper_tri = [np.array([coord[0], coord[1], z + height], dtype=np.float32) for coord in tri]
            triangles.append(upper_tri)

        # Create side triangles
        for i in range(0, length):
            triangles.append([vertices[i], vertices[length + i], vertices[length + ((i + 1) % length)]])
            triangles.append([vertices[i], vertices[length + ((i + 1) % length)], vertices[((i + 1) % length)]])

        # If the obj creation flag is defined, create triangles for the obj
        if create_obj:
            for tri in poly_triangles:
                lower_tri = [self.find_coordinate_index(coordinates, coord) for coord in reversed(tri)]
                triangles_id.append(lower_tri)
                upper_tri = [self.find_coordinate_index(coordinates, coord) + length for coord in tri]
                triangles_id.append(upper_tri)

            for i in range(0, length):
                triangles_id.append([i, length + i, length + ((i + 1) % length)])
                triangles_id.append([i, length + ((i + 1) % length), ((i + 1) % length)])

            # keep vertices and triangles in order to create Obj model
            self.vertices = vertices
            self.triangles = triangles_id

        self.geom.triangles.append(triangles)

        self.set_box()

        return True

    def get_geojson_id(self):
        return super().get_id()

    def set_geojson_id(self, id):
        return super().set_id(id)


class Geojsons(ObjectsToTile):
    """
        A decorated list of ObjectsToTile type objects.
    """

    def __init__(self, objects=None):
        super().__init__(objects)

    @staticmethod
    def retrieve_geojsons(path, properties, obj_name, is_roof):
        """
        :param path: a path to a directory

        :return: a list of geojson.
        """

        geojson_dir = listdir(path)

        features = list()
        geometries = Geojsons()

        # Used only when creating an .obj model
        vertices = list()
        triangles = list()
        vertice_offset = 1
        center = [0, 0, 0]

        # Reads and parse every features from the file(s)
        for geojson_file in geojson_dir:
            if(os.path.isfile(os.path.join(path, geojson_file))):
                if(".geojson" in geojson_file or ".json" in geojson_file):
                    # Get id from its name
                    id = geojson_file.replace('json', '')
                    with open(os.path.join(path, geojson_file)) as f:
                        gjContent = json.load(f)

                    k = 0
                    for feature in gjContent['features']:

                        if "ID" in feature['properties']:
                            feature_id = feature['properties']['ID']
                        else:
                            feature_id = id + str(k)
                            k += 1
                        geojson = Geojson(feature_id)
                        if(geojson.parse_geojson(feature, properties, is_roof)):
                            features.append(geojson)

        create_obj = obj_name is not None

        for feature in features:
            # Create geometry as expected from GLTF from an geojson file
            if(feature.parse_geom(create_obj)):
                geometries.append(feature)

                if create_obj:
                    # Add triangles and vertices to create an obj
                    for vertice in feature.vertices:
                        vertices.append(vertice)
                    for triangle in feature.triangles:
                        triangles.append([v + vertice_offset for v in triangle])
                    vertice_offset += len(feature.vertices)
                    for i in range(0, len(feature.center)):
                        center[i] += feature.center[i]

        if create_obj:
            center[:] = [c / len(geometries) for c in center]
            file_name = obj_name
            f = open(os.path.join(file_name), "w")
            f.write("# " + file_name + "\n")

            for vertice in vertices:
                f.write("v " + str(vertice[0] - center[0]) + " " + str(vertice[1] - center[1]) + " " + str(vertice[2] - center[2]) + "\n")

            for triangle in triangles:
                f.write("f " + str(int(triangle[0])) + " " + str(int(triangle[1])) + " " + str(int(triangle[2])) + "\n")

        return geometries
