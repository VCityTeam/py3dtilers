# -*- coding: utf-8 -*-
import re

import numpy as np
import triangle as tr
from shapely.geometry import Polygon

from ..Common import Feature, FeatureList


# The GeoJson file contains the ground surface of urban elements, mainly buildings.
# Those elements are called "features", each feature has its own ground coordinates.
# The goal here is to take those coordinates and create a box from it.
# To do this, we compute the center of the lower face
# Then we create the triangles of this face
# and duplicate it with a Z offset to create the upper face
# Then we create the side triangles to connect the upper and the lower faces
class Geojson(Feature):
    """
    The Python representation of a GeoJSON feature.
    A Geojson instance has a geometry and properties.
    """

    n_feature = 0

    # Default height will be used if no height is found when parsing the data
    default_height = 10

    # Default Z will be used if no Z is found in the feature coordinates
    default_z = 0

    # Those values are used to set the color of the features
    attribute_values = list()  # Contains all the values of a semantic attribute
    attribute_min = np.Inf  # Contains the min value of a numeric attribute
    attribute_max = np.NINF  # Contains the max value of a numeric attribute

    def __init__(self, id=None, feature_properties=None, feature_geometry=None):
        super().__init__(id)

        self.feature_properties = feature_properties
        self.feature_geometry = feature_geometry

        self.height = 0
        """How high we extrude the polygon when creating the 3D geometry"""

        self.polygon = list()
        self.custom_triangulation = False

    def custom_triangulate(self, coordinates):
        """
        Custom triangulation method used when we triangulate buffered lines.
        :param coordinates: an array of 3D points ([x, y, Z])

        :return: a list of triangles
        """
        triangles = list()
        length = len(coordinates)

        for i in range(0, (length // 2) - 1):
            triangles.append([coordinates[i], coordinates[length - 1 - i], coordinates[i + 1]])
            triangles.append([coordinates[i + 1], coordinates[length - 1 - i], coordinates[length - 2 - i]])

        return triangles

    def set_z(self, coordinates, z):
        """
        Set the Z value of each coordinate of the feature.
        The Z can be the name of a property to read in the feature or a float.
        :param coordinates: the coordinates of the feature
        :param z: the value of the z
        """
        z_value = Geojson.default_z
        if z != 'NONE':
            if z.replace('.', '', 1).isdigit():
                z_value = float(z)
            else:
                if z in self.feature_properties and self.feature_properties[z] is not None:
                    z_value = self.feature_properties[z]
                elif self.feature_properties[z] is None:
                    z_value = Geojson.default_z
                else:
                    print("No propertie called " + z + " in feature " + str(Geojson.n_feature) + ". Set Z to default value (" + str(Geojson.default_z) + ").")
        for coord in coordinates:
            if len(coord) < 3:
                coord.append(z_value)
            elif z != 'NONE':
                coord[2] = z_value

    def parse_geojson(self, target_properties, is_roof=False, color_attribute=('NONE', 'numeric')):
        """
        Parse a feature to extract the height and the coordinates of the feature.
        :param target_properties: the names of the properties to read
        :param Boolean is_roof: False when the coordinates are on floor level
        """
        # Current feature number (used for debug)
        Geojson.n_feature += 1

        # If precision is equal to 9999, it means Z values of the features are missing, so we skip the feature
        prec_name = target_properties[target_properties.index('prec') + 1]
        if prec_name != 'NONE' and prec_name in self.feature_properties and self.feature_properties[prec_name] is not None:
            if self.feature_properties[prec_name] >= 9999.:
                return False

        height_name = target_properties[target_properties.index('height') + 1]
        if height_name.replace('.', '', 1).isdigit():
            self.height = float(height_name)
        else:
            if height_name in self.feature_properties:
                if self.feature_properties[height_name] is not None and self.feature_properties[height_name] > 0:
                    self.height = self.feature_properties[height_name]
                else:
                    self.height = Geojson.default_height
            else:
                print("No propertie called " + height_name + " in feature " + str(Geojson.n_feature) + ". Set height to default value (" + str(Geojson.default_height) + ").")
                self.height = Geojson.default_height

        if color_attribute[0] in self.feature_properties:
            attribute = self.feature_properties[color_attribute[0]]
            if color_attribute[1] == 'numeric':
                if attribute > Geojson.attribute_max:
                    Geojson.attribute_max = attribute
                if attribute < Geojson.attribute_min:
                    Geojson.attribute_min = attribute
            else:
                if attribute not in Geojson.attribute_values:
                    Geojson.attribute_values.append(attribute)

    def update_seg(self, holes, seg):
        """
        Update the segments of the feature.
        :param holes: the holes of the feature
        :param seg: the segments of the feature
        """

        cond = len(holes) - 1 + len(seg)
        first_index = len(seg)
        for i, _ in enumerate(holes, first_index):
            if i == cond:
                break
            seg.extend([(i, i + 1)])

        seg.extend([(len(seg), first_index)])
        return seg

    def remove_int_ring_with_duplicate_points_from_exterior_ring(self):
        """
        Removes any interior rings that contain points duplicated in the exterior ring.

        This function is specifically designed to address an issue with the 'triangle'
        library, where duplicate points between the exterior and interior rings can
        cause segmentation faults. By removing interior rings that share points with
        the exterior ring, this function ensures the geometric integrity of the shape
        and prevents such faults.

        The function operates directly on the instance's 'exterior_ring' and
        'interior_rings' attributes. It modifies 'interior_rings' in place, removing
        any rings that contain points found in the 'exterior_ring'.
        """

        seen = set(map(tuple, self.exterior_ring))

        self.interior_rings = [
            ring
            for ring in self.interior_rings
            if not any(tuple(coord) in seen for coord in ring)
        ]

    def create_wall_vertices(self, ring):
        """
        Create the vertices of the side triangles of the feature.
        :param ring: the coordinates of the feature
        """

        height = self.height
        ring_length = len(ring)
        vertices = [None] * (2 * ring_length)
        for j, coord in enumerate(ring):
            vertices[j] = np.array([coord[0], coord[1], coord[2]])
            vertices[j + ring_length] = np.array([coord[0], coord[1], coord[2] + height])
        return vertices

    def prepare_geometry(self):
        """
        Prepares the geometric data for triangulation.

        This method processes the exterior and interior rings of a geometry to create a set of vertices and segments.
        It also identifies holes in the geometry if any are present.

        Returns:
            dict: A dictionary containing vertices and segments for triangulation.
                It includes holes if they exist in the geometry.
        """

        exterior_ring = self.exterior_ring
        interior_rings = self.interior_rings

        all_vertices = [coord[:2] for coord in exterior_ring]
        for ctyard_wall_verts in interior_rings:
            all_vertices.extend([coord[:2] for coord in ctyard_wall_verts])

        seg = []
        for i, _ in enumerate(exterior_ring, len(seg)):
            if i == len(exterior_ring) - 1:
                break
            seg.append((i, i + 1))
        seg.append((len(exterior_ring) - 1, 0))

        holes = []
        for polygon in interior_rings:
            P = Polygon(polygon)
            centroid = P.representative_point()
            point_str = str(centroid)
            coordinates = re.findall(r"[-+]?\d*\.\d+|\d+", point_str)
            x, y = map(float, coordinates[-2:])
            holes.append([x, y])
            Geojson().update_seg(polygon, seg)

        A = dict(vertices=all_vertices, segments=seg)

        if holes:
            A["holes"] = holes

        return A

    def perform_triangulation(self, A):
        """
        Performs triangulation on the given geometric data.

        This method decides between custom triangulation and default triangulation based on the 'custom_triangulation' attribute.

        Parameters:
            A (dict): Geometric data containing vertices, segments, and optionally holes.

        Returns:
            dict or object: Result of the triangulation process. The type of the return value depends on the triangulation method used.
        """

        if self.custom_triangulation:
            return self.custom_triangulate(self.exterior_ring)
        else:
            try:
                return tr.triangulate(A, "p")
            except Exception as e:
                print("Error in triangulation: ", e, " on ", self.id)

    def create_upper_triangles(self, poly_triangles, triangles):
        """
        Creates upper triangles for the 3D geometry.

        This method takes the result of the triangulation process and generates upper triangles by adjusting the z-coordinate based on the height.

        Parameters:
            poly_triangles (list or dict): The result of the triangulation process.
            triangles (list): A list to which the generated upper triangles will be appended.
        """

        for tri in poly_triangles:
            upper_tri = [np.array([coord[0], coord[1], coord[2] + self.height]) for coord in tri]
            triangles.append(upper_tri)

    def add_side_triangles(self, wall_vertices, index, length, triangles):
        """
        Adds side triangles for a given segment of a ring.

        This method calculates and appends two side triangles for a segment, based on the provided vertices.

        Parameters:
            wall_vertices (list): List of vertices for the wall.
            index (int): Current index in the vertices list.
            length (int): The total number of segments in the ring.
            triangles (list): List to which the calculated triangles will be appended.
        """

        triangles.append([wall_vertices[index], wall_vertices[length + index], wall_vertices[length + ((index + 1) % length)],])
        triangles.append([wall_vertices[index], wall_vertices[length + ((index + 1) % length)], wall_vertices[((index + 1) % length)],])

    def create_side_triangles(self, triangles):
        """
        Generates side triangles for both the exterior and interior rings of the geometry.

        This method handles the creation of side triangles for the entire structure, including both the exterior ring and any interior rings (courtyards).

        Parameters:
            triangles (list): A list to which the generated side triangles will be appended.
        """

        exterior_ring = self.exterior_ring
        interior_rings = self.interior_rings

        building_wall_vertices = self.create_wall_vertices(exterior_ring)

        self.process_ring_for_side_triangles(building_wall_vertices, triangles)

        for ctyard_wall_verts in interior_rings:
            ctyard_wall_vertices = self.create_wall_vertices(ctyard_wall_verts)
            self.process_ring_for_side_triangles(ctyard_wall_vertices, triangles)

    def process_ring_for_side_triangles(self, ring_vertices, triangles):
        """
        Processes a single ring to create side triangles.

        Given a set of vertices for a ring, this method iterates through them to create side triangles.

        Parameters:
            ring_vertices (list): List of vertices for the ring.
            triangles (list): List to which the created side triangles will be appended.
        """

        ring_length = len(ring_vertices) // 2
        for i in range(ring_length):
            self.add_side_triangles(ring_vertices, i, ring_length, triangles)

    def create_triangles_with_elevation(self, poly_triangles, elevation):
        """
        Creates a list of triangles with added elevation.

        This method processes the triangulation result to add elevation to each vertex, forming 3D triangles.

        Parameters:
            poly_triangles (dict): Result of triangulation, containing vertices and triangle indices.
            elevation (float): The elevation to be added to each vertex.

        Returns:
            list: List of 3D triangles with added elevation.
        """

        triangles_with_ele = []

        for triangle_indices in poly_triangles["triangles"]:
            triangle = []
            for idx in triangle_indices:
                vertex_with_z = list(poly_triangles["vertices"][idx]) + [elevation]
                triangle.append(vertex_with_z)
            triangles_with_ele.append(tuple(triangle))

        return triangles_with_ele

    def remove_duplicate_points_within_exterior_ring(self):
        """
        Prevents segmentation faults in the 'triangle' library by removing
        duplicate points from the exterior ring.

        This function is essential when working with the 'triangle' library, as
        duplicated points in the exterior ring can cause segmentation faults during
        triangulation. By iterating through the exterior ring and removing any
        duplicated points, it ensures that each point in the exterior ring is unique.

        Operates directly on the instance's 'exterior_ring' attribute, modifying
        it in place. After execution, the 'exterior_ring' contains only unique points.
        """

        seen = set()
        unique_coords = []

        for coords in self.exterior_ring:
            coords_tuple = tuple(coords)
            if coords_tuple not in seen:
                unique_coords.append(list(coords_tuple))
                seen.add(coords_tuple)

        self.exterior_ring = unique_coords

    def remove_duplicate_points_within_interior_rings(self):
        """
        Prevents segmentation faults in the 'triangle' library by removing
        duplicate points from interior rings.

        This function addresses a critical issue when using the 'triangle' library,
        where duplicated points in interior rings can lead to segmentation faults
        during triangulation. It iterates through each interior ring of the polygon,
        removing any duplicated points to ensure the uniqueness of the points within
        the interior geometry.

        Directly modifies the instance's 'interior_rings' attribute. After this
        function is executed, each interior ring in the 'interior_rings' attribute
        will only contain unique points, thus preventing potential triangulation
        issues.
        """

        seen = set()
        unique_rings = []

        for rings in self.interior_rings:
            unique_coords = []
            for coord in rings:
                coord_tuple = tuple(coord)
                if coord_tuple not in seen:
                    unique_coords.append(list(coord_tuple))
                    seen.add(coord_tuple)
            if unique_coords:
                unique_rings.append(unique_coords)

        self.interior_rings = unique_rings

    def parse_geom(self):
        """
        Creates the 3D extrusion of the feature.
        """
        triangles = list()

        A = self.prepare_geometry()

        if len(A["vertices"]) < 3:
            return

        poly_triangles = self.perform_triangulation(A)

        if self.custom_triangulation:
            self.create_upper_triangles(poly_triangles, triangles)
        else:
            elevation = self.exterior_ring[0][2]
            triangles_with_ele = self.create_triangles_with_elevation(poly_triangles, elevation)
            self.create_upper_triangles(triangles_with_ele, triangles)

        self.create_side_triangles(triangles)
        self.geom.triangles.append(triangles)
        self.set_box()

    def get_geojson_id(self):
        return super().get_id()

    def set_geojson_id(self, id):
        return super().set_id(id)


class Geojsons(FeatureList):
    """
    A decorated list of Geojson instances.
    """

    def __init__(self, objects=None):
        super().__init__(objects)

    @staticmethod
    def parse_geojsons(features, properties, is_roof=False, color_attribute=('NONE', 'numeric')):
        """
        Create 3D features from the GeoJson features.
        :param features: the features to parse from the GeoJSON
        :param properties: the properties used when parsing the features
        :param is_roof: substract the height from the features coordinates

        :return: a list of triangulated Geojson instances.
        """
        feature_list = list()

        for feature in features:
            if not feature.parse_geojson(properties, is_roof, color_attribute):
                continue

            feature.remove_int_ring_with_duplicate_points_from_exterior_ring()
            feature.remove_duplicate_points_within_exterior_ring()
            feature.remove_duplicate_points_within_interior_rings()

            # Create geometry as expected from GLTF from an geojson file
            feature.parse_geom()
            feature_list.append(feature)

        return Geojsons(features)
