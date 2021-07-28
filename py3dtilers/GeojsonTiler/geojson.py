# -*- coding: utf-8 -*-
import os
from os import listdir
import sys
import numpy as np
import json

import tripy
from shapely.geometry import Point, Polygon

from ..Common import ObjectToTile, ObjectsToTile
from .PolygonDetection import PolygonDetector


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
        # Current feature number
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

    defaultGroupOffset = 50

    def __init__(self, objs=None):
        super().__init__(objs)

    @staticmethod
    def round_coordinate(coordinate, base):
        """Round the coordinate to the closest multiple of 'base'"""

        rounded_coord = coordinate
        for i in range(0, len(coordinate)):
            rounded_coord[i] = base * round(coordinate[i] / base)
        return rounded_coord

    @staticmethod
    def group_features_by_polygons(features, path):
        try:
            polygon_path = os.path.join(path, "polygons")
            polygon_dir = listdir(polygon_path)
        except FileNotFoundError:
            print("No directory called 'polygons' in", path, ". Please, place the polygons to read in", polygon_path)
            print("Exiting")
            sys.exit(1)
        polygons = list()
        for polygon_file in polygon_dir:
            if(".geojson" in polygon_file or ".json" in polygon_file):
                with open(os.path.join(polygon_path, polygon_file)) as f:
                    gjContent = json.load(f)
                for feature in gjContent['features']:
                    coords = feature['geometry']['coordinates'][0][:-1]
                    polygons.append(Polygon(coords))
        return Geojsons.distribute_features_in_polygons(features, polygons)

    @staticmethod
    def group_features_by_roads(features, path):
        try:
            road_path = os.path.join(path, "roads")
            road_dir = listdir(road_path)
        except FileNotFoundError:
            print("No directory called 'roads' in", path, ". Please, place the roads to read in", road_path)
            print("Exiting")
            sys.exit(1)
        lines = list()
        for road_file in road_dir:
            if(".geojson" in road_file or ".json" in road_file):
                with open(os.path.join(road_path, road_file)) as f:
                    gjContent = json.load(f)
                for feature in gjContent['features']:
                    if 'type' in feature['geometry'] and feature['geometry']['type'] == 'LineString':
                        lines.append(feature['geometry']['coordinates'])
        print("Roads parsed from file")

        p = PolygonDetector(lines)
        polygons = p.create_polygons()
        return Geojsons.distribute_features_in_polygons(features, polygons)

    @staticmethod
    def group_features_by_cube(features, size):
        """Group features which are in the same cube of size 'size'"""
        features_dict = {}

        # Create a dictionary key: cubes center (x,y,z); value: list of features index
        for i in range(0, len(features)):
            closest_cube = Geojsons.round_coordinate(features[i].center, size)
            if tuple(closest_cube) in features_dict:
                features_dict[tuple(closest_cube)].append(i)
            else:
                features_dict[tuple(closest_cube)] = [i]
        return Geojsons.group_features(features, features_dict)

    @staticmethod
    def group_features(features, dictionary):
        k = 0
        grouped_features = list()
        grouped_features_dict = {}
        for key in dictionary:
            geojson = Geojson("group" + str(k))
            z = np.Inf
            height = 0
            coords = list()
            grouped_features_dict[k] = []
            for j in dictionary[key]:
                grouped_features_dict[k].append(j)
                height += features[j].height
                if z > features[j].z:
                    z = features[j].z
                for coord in features[j].coords:
                    coords.append(coord)

            geojson.coords = coords
            geojson.z = z
            geojson.height = height / len(dictionary[key])
            center = geojson.get_center(coords)
            geojson.center = [center[0], center[1], center[2] + geojson.height / 2]
            grouped_features.append(geojson)
            k += 1
        return grouped_features

    @staticmethod
    def distribute_features_in_polygons(features, polygons):
        features_dict = {}
        features_without_poly = list()
        for i in range(0, len(features)):
            p = Point(features[i].center)
            in_polygon = False
            for index, polygon in enumerate(polygons):
                if p.within(polygon):
                    if index in features_dict:
                        features_dict[index].append(i)
                    else:
                        features_dict[index] = [i]
                    in_polygon = True
                    break
            if not in_polygon:
                features_without_poly.append(features[i])

        grouped_features = Geojsons.group_features(features, features_dict)
        return grouped_features

    @staticmethod
    def retrieve_geojsons(path, group, properties, obj_name, is_roof):
        """
        :param path: a path to a directory

        :return: a list of geojson.
        """

        geojson_dir = listdir(path)

        vertices = list()
        triangles = list()
        features = list()
        vertice_offset = 1
        center = [0, 0, 0]
        objects = list()

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

        if 'road' in group:
            grouped_features = Geojsons.group_features_by_roads(features, path)
        elif 'polygon' in group:
            grouped_features = Geojsons.group_features_by_polygons(features, path)
        elif 'cube' in group:
            try:
                size = int(group[group.index('cube') + 1])
            except IndexError:
                size = Geojsons.defaultGroupOffset
            grouped_features = Geojsons.group_features_by_cube(features, size)
        else:
            grouped_features = features

        create_obj = obj_name is not None

        for feature in grouped_features:
            # Create geometry as expected from GLTF from an geojson file
            if(feature.parse_geom(create_obj)):
                objects.append(feature)

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
            center[:] = [c / len(objects) for c in center]
            file_name = obj_name
            f = open(os.path.join(file_name), "w")
            f.write("# " + file_name + "\n")

            for vertice in vertices:
                f.write("v " + str(vertice[0] - center[0]) + " " + str(vertice[1] - center[1]) + " " + str(vertice[2] - center[2]) + "\n")

            for triangle in triangles:
                f.write("f " + str(int(triangle[0])) + " " + str(int(triangle[1])) + " " + str(int(triangle[2])) + "\n")

        return Geojsons(objects)
