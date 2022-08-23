from shapely.geometry import Point, Polygon
from ..Common import FeatureList, ExtrudedPolygon
from typing import TYPE_CHECKING, List

if TYPE_CHECKING:
    from ..Common import Feature, GeometryNode


class LodFeatureList(FeatureList):

    def __init__(self, features=None, features_node: 'GeometryNode' = None):
        super().__init__(features)
        self.features_node = features_node
        self.centroid = features_node.feature_list.get_centroid()


class Lod1FeatureList(LodFeatureList):

    def set_features_geom(self, user_arguments=None):
        """
        Set the geometry of the features.
        Keep only the features with geometry.
        """
        for i, feature in enumerate(self.features_node.feature_list):
            extruded_polygon = ExtrudedPolygon("lod1_" + str(i), [feature])
            extruded_polygon.set_geom()
            self.append(extruded_polygon)
        self.features_node = None


class LoaFeatureList(LodFeatureList):

    loa_index = 0

    def __init__(self, features=None, polygons=list(), features_node: 'GeometryNode' = None):
        super().__init__(features, features_node=features_node)
        self.polygons = polygons

    def set_features_geom(self, user_arguments=None):
        """
        Set the geometry of the features.
        Keep only the features with geometry.
        """
        features = self.features_node.feature_list.get_features().copy()

        for polygon in self.polygons:
            feature_list = FeatureList(self.find_features_in_polygon(features, Polygon(polygon)))
            if len(feature_list) > 0:
                [features.remove(feature) for feature in feature_list]
                self.append(self.create_loa(feature_list, polygon))

        for feature in features:
            self.append(self.create_loa(FeatureList([feature])))

        self.features_node = None

    def find_features_in_polygon(self, features: List['Feature'], polygon: 'Polygon'):
        """
        Find all the features which are in the polygon.
        :param features: a list of Feature
        :param polygon: a Shapely Polygon
        :return: a list of Feature
        """
        features_in_polygon = list()
        for feature in features:
            p = Point(feature.get_centroid())
            if p.within(polygon):
                features_in_polygon.append(feature)
        return features_in_polygon

    def create_loa(self, feature_list: 'FeatureList', polygon: 'Polygon' = None):
        """
        Create a LOA (3D extrusion of a polygon). The LOA is a 3D geometry containing a group of features.
        :param feature_list: the features contained in the LOA
        :param polygon: a polygon as list of 3D points
        :param int index: an index used for the LOA identifier

        :return: a 3D extrusion of the polygon
        """
        index = LoaFeatureList.loa_index
        LoaFeatureList.loa_index += 1

        extruded_polygon = ExtrudedPolygon("loa_" + str(index), feature_list, polygon=polygon)
        return extruded_polygon
