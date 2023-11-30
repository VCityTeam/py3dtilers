import os
from os import listdir
import json
from shapely.geometry import Point, Polygon
from ..Common import FeatureList
from ..Common import kd_tree
from typing import List


class Group():
    """
    Contains an instance of FeatureList
    It can also contain additional polygon points (used to create LOA nodes)
    """

    def __init__(self, feature_list: FeatureList, polygons=list()):
        self.feature_list = feature_list
        self.polygons = polygons

    def get_centroid(self):
        """
        Get the centroid of the group.
        :return: a 3D point ([x, y, z])
        """
        return self.feature_list.get_centroid()

    def round_coordinates(self, coordinates, base):
        """
        Round the coordinates to the closer multiple of a base.
        :param coordinates: a 3D point ([x, y, z])
        :param int base: the base used to round the coordinates

        :return: a 3D point rounded to the closer multiples of the base
        """
        rounded_coord = coordinates
        for i in range(0, len(coordinates)):
            rounded_coord[i] = base * round(coordinates[i] / base)
        return rounded_coord

    def add_materials(self, materials):
        """
        Keep only the materials used by the features of this group,
        among all the materials created, and add them to the features.
        :param materials: an array of all the materials
        """
        seen_mat_indexes = dict()
        group_materials = []
        for feature in self.feature_list:
            mat_index = feature.material_index
            if mat_index not in seen_mat_indexes:
                seen_mat_indexes[mat_index] = len(group_materials)
                group_materials.append(materials[mat_index])
            feature.material_index = seen_mat_indexes[mat_index]
        self.feature_list.set_materials(group_materials)


class Groups():
    """
    Contains a list of Group
    """

    # Used to put in a same group the features which are in a same 1000 m^3 cube.
    DEFAULT_CUBE_SIZE = 1000

    def __init__(self, feature_list: FeatureList, polygons_path=None, kd_tree_max=500, as_lods=False):
        """
        Distribute the features contained in feature_list into different Group
        The way to distribute the features depends on the parameters
        :param feature_list: an instance of FeatureList containing features to distribute into Group
        :param polygons_path: the path to a folder containing polygons as .geojson files.
        When this param is not None, it means we want to group features by polygons
        :param kd_tree_max: the maximum number of features in each list created by the kd_tree
        """
        if ((type(feature_list) is list)):
            self.group_array_of_feature_list(feature_list)
        else:
            self.materials = feature_list.materials
            if polygons_path is not None:
                self.group_objects_by_polygons(feature_list, polygons_path)
            elif as_lods:
                self.group_feature_list(feature_list)
            else:
                self.group_objects_with_kdtree(feature_list, kd_tree_max)
            self.set_materials(self.materials)

    def get_groups_as_list(self):
        """
        Return the groups as a list.
        :return: the groups as list
        """
        return self.groups

    def set_materials(self, materials):
        """
        Set the materials of each group.
        :param materials: an array of all the materials
        """
        for group in self.groups:
            group.add_materials(materials)

    def group_array_of_feature_list(self, feature_lists_array: List[FeatureList]):
        """
        Create one Group per FeatureList.
        :param feature_lists_array: a list of FeatureList
        """
        self.groups = [Group(feature_list) for feature_list in feature_lists_array]

    def group_feature_list(self, feature_list: FeatureList):
        """
        Create one Group per Feature of a FeatureList.
        :param feature_list: a FeatureList
        """
        self.groups = [Group(FeatureList([feature])) for feature in feature_list]

    def group_objects_with_kdtree(self, feature_list: FeatureList, kd_tree_max=500):
        """
        Create groups of features. The features are distributed into FeatureList of (by default) max 500 features.
        The distribution depends on the centroid of each feature.
        :param feature_list: a FeatureList
        :param kd_tree_max: the maximum number of features in each FeatureList
        """
        groups = list()
        objects = kd_tree(feature_list, kd_tree_max)
        for feature_list in objects:
            group = Group(feature_list)
            groups.append(group)
        self.groups = groups

    def group_objects_by_polygons(self, feature_list: FeatureList, polygons_path):
        """
        Load the polygons from GeoJSON files.
        Group the features depending in which polygon they are contained.
        :param feature_list: all the features
        :param polygons_path: the path to the file(s) containing polygons
        """
        polygons = list()
        files = []

        if os.path.isdir(polygons_path):
            geojson_dir = listdir(polygons_path)
            for geojson_file in geojson_dir:
                file_path = os.path.join(polygons_path, geojson_file)
                if os.path.isfile(file_path):
                    files.append(file_path)
        else:
            files.append(polygons_path)

        # Read all the polygons in the file(s)
        for file in files:
            if ".geojson" in file or ".json" in file:
                with open(file) as f:
                    gjContent = json.load(f)
                for feature in gjContent['features']:
                    if feature['geometry']['type'] == 'Polygon':
                        coords = feature['geometry']['coordinates'][0][:-1]
                    if feature['geometry']['type'] == 'MultiPolygon':
                        coords = feature['geometry']['coordinates'][0][0][:-1]
                    polygons.append(Polygon(coords))
        self.groups = self.distribute_objects_in_polygons(feature_list, polygons)

    def distribute_objects_in_polygons(self, feature_list: FeatureList, polygons):
        """
        Distribute the features in the polygons.
        The features in the same polygon are grouped together. The Group created will also contain the points of the polygon.
        If a feature is not in any polygon, create a Group containing only this feature. This group won't have addtional points.
        :param polygons: a list of Shapely polygons
        """

        features_dict = {}
        features_without_poly = list()

        # For each feature, find the polygon containing it
        for i, feature in enumerate(feature_list):
            p = Point(feature.get_centroid())
            in_polygon = False
            for index, polygon in enumerate(polygons):
                if p.within(polygon):
                    if index not in features_dict:
                        features_dict[index] = []
                    features_dict[index].append(i)
                    in_polygon = True
                    break
            if not in_polygon:
                features_without_poly.append(i)

        # Create a list of Group
        groups = list()

        for key in features_dict:
            polygon = polygons[key].exterior.coords[:-1]
            contained_features = FeatureList([feature_list[i] for i in features_dict[key]])
            group = Group(contained_features, polygons=[polygon])
            groups.append(group)

        for feature_index in features_without_poly:
            group = Group(FeatureList([feature_list[feature_index]]))
            groups.append(group)

        return self.distribute_groups_in_cubes(groups, Groups.DEFAULT_CUBE_SIZE)

    def distribute_groups_in_cubes(self, groups: List[Group], cube_size):
        """
        Merges together the groups in order to reduce the number of tiles.
        The groups are distributed into cubes of a grid. The groups in the same cube are merged together.
        :param groups: the groups to distribute into cubes
        :param cube_size: the size of the cubes

        :return: merged groups
        """
        groups_dict = {}

        # Create a dictionary key: cubes center (x,y,z), with geometry (boolean); value: list of groups index
        for i in range(0, len(groups)):
            closest_cube = groups[i].round_coordinates(groups[i].get_centroid(), cube_size)
            if tuple(closest_cube) in groups_dict:
                groups_dict[tuple(closest_cube)].append(i)
            else:
                groups_dict[tuple(closest_cube)] = [i]

        # Merge the groups in the same cube and create new groups
        groups_in_cube = list()
        for cube in groups_dict:
            groups_in_cube.append(self.merge_groups_together(groups, groups_dict[cube]))
        return groups_in_cube

    def merge_groups_together(self, groups: List[Group], group_indexes):
        """
        Creates a Group from a list of Groups
        :param groups: all the groups
        :param group_indexes: the indexes of the groups to merge together

        :return: a new group containing the features of all the groups
        """
        features = list()
        polygons = list()
        for index in group_indexes:
            features.extend(groups[index].feature_list)
            polygons.extend(groups[index].polygons)
        return Group(FeatureList(features), polygons=polygons)
