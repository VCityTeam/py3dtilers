# -*- coding: utf-8 -*-
import numpy as np
from earclip import triangulate

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

    # Default height will be used if no height is found when parsing the data
    default_height = 2

    def __init__(self, id=None, feature_properties=None, feature_geometry=None):
        super().__init__(id)

        self.feature_properties = feature_properties
        self.feature_geometry = feature_geometry

        self.height = 0
        """How high we extrude the polygon when creating the 3D geometry"""

        self.polygon = list()
        self.custom_triangulation = False

    def custom_triangulate(self, coordinates):
        triangles = list()
        length = len(coordinates)

        for i in range(0, (length // 2) - 1):
            triangles.append([coordinates[i], coordinates[length - 1 - i], coordinates[i + 1]])
            triangles.append([coordinates[i + 1], coordinates[length - 1 - i], coordinates[length - 2 - i]])

        return triangles

    def parse_geojson(self, target_properties, is_roof=False):
        """
        Parse a feature of the .geojson file to extract the height and the coordinates of the feature.
        """
        # Current feature number (used for debug)
        Geojson.n_feature += 1

        # If precision is equal to 9999, it means Z values of the features are missing, so we skip the feature
        prec_name = target_properties[target_properties.index('prec') + 1]
        if prec_name != 'NONE':
            if prec_name in self.feature_properties:
                if self.feature_properties[prec_name] >= 9999.:
                    return False
            else:
                print("No propertie called " + prec_name + " in feature " + str(Geojson.n_feature))

        height_name = target_properties[target_properties.index('height') + 1]
        if height_name.replace('.', '', 1).isdigit():
            self.height = float(height_name)
        else:
            if height_name in self.feature_properties:
                if self.feature_properties[height_name] > 0:
                    self.height = self.feature_properties[height_name]
                else:
                    self.height = Geojson.default_height
            else:
                print("No propertie called " + height_name + " in feature " + str(Geojson.n_feature) + ". Set height to default value (" + str(Geojson.default_height) + ").")
                self.height = Geojson.default_height

    def parse_geom(self):
        """
        Creates the 3D extrusion of the feature.
        """
        height = self.height
        coordinates = self.polygon
        length = len(coordinates)

        # Contains the triangles vertices. Used to create 3D tiles
        triangles = list()
        vertices = [None] * (2 * length)

        for i, coord in enumerate(coordinates):
            vertices[i] = np.array([coord[0], coord[1], coord[2]], dtype=np.float32)
            vertices[i + length] = np.array([coord[0], coord[1], coord[2] + height], dtype=np.float32)

        # Triangulate the feature footprint
        if self.custom_triangulation:
            poly_triangles = self.custom_triangulate(coordinates)
        else:
            poly_triangles = triangulate(coordinates)

        # Create upper face triangles
        for tri in poly_triangles:
            upper_tri = [np.array([coord[0], coord[1], coord[2] + height], dtype=np.float32) for coord in tri]
            triangles.append(upper_tri)

        # Create side triangles
        for i in range(0, length):
            triangles.append([vertices[i], vertices[length + i], vertices[length + ((i + 1) % length)]])
            triangles.append([vertices[i], vertices[length + ((i + 1) % length)], vertices[((i + 1) % length)]])

        self.geom.triangles.append(triangles)
        self.set_box()

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
    def parse_geojsons(features, properties, is_roof=False):
        """
        :param features: the features to parse
        :param properties: the properties used when parsing the features
        :param is_roof: substract the height from the features coordinates

        :return: a list of Geojson instances.
        """
        geometries = list()

        for feature in features:
            if not feature.parse_geojson(properties, is_roof):
                continue

            # Create geometry as expected from GLTF from an geojson file
            feature.parse_geom()
            geometries.append(feature)

        return Geojsons(geometries)
