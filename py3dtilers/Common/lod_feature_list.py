import numpy as np
from ..Common import FeatureList, ExtrudedPolygon


class LodFeatureList(FeatureList):

    def __init__(self, objects=None, features_node=None):
        super().__init__(objects)
        self.features_node = features_node
        self.centroid = features_node.feature_list.get_centroid()

    def get_centroid(self):
        return self.centroid


class Lod1FeatureList(LodFeatureList):

    def set_features_geom(self, user_arguments=None):
        """
        Set the geometry of the features.
        Keep only the features with geometry.
        """
        for i, feature in enumerate(self.features_node.feature_list):
            extruded_polygon = ExtrudedPolygon("lod1_" + str(i), [feature])
            extruded_polygon.set_geom()
            self.objects.append(extruded_polygon)
        self.features_node = None


class LoaFeatureList(LodFeatureList):

    loa_index = 0

    def __init__(self, objects=None, points_dict=None, additional_points=None, features_node=None):
        super().__init__(objects, features_node=features_node)
        self.points_dict = points_dict
        self.additional_points = additional_points

    def set_features_geom(self, user_arguments=None):
        """
        Set the geometry of the features.
        Keep only the features with geometry.
        """
        for key in self.points_dict:
            contained_objects = FeatureList([self.features_node.feature_list[i] for i in self.points_dict[key]])
            loa = self.create_loa_from_polygon(contained_objects, self.additional_points[key], LoaFeatureList.loa_index)
            loa.set_geom()
            LoaFeatureList.loa_index += 1
            self.objects.append(loa)
        self.features_node = None

    def create_loa_from_polygon(self, feature_list, polygon_points, index=0):
        """
        Create a LOA (3D extrusion of a polygon). The LOA is a 3D geometry containing a group of features.
        :param feature_list: the features contained in the LOA
        :param polygon_points: a polygon as list of 3D points
        :param int index: an index used for the LOA identifier

        :return: a 3D extrusion of the polygon
        """
        centroid = np.array([0, 0, 0], dtype=np.float64)
        for feature in feature_list:
            centroid += feature.get_centroid()
        centroid /= len(feature_list)

        extruded_polygon = ExtrudedPolygon("loa_" + str(index), feature_list, polygon=polygon_points)
        return extruded_polygon
