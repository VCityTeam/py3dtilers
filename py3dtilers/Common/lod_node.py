from ..Common import FeatureList, Feature, GeometryNode
from ..Common import ExtrudedPolygon


class Lod1Node(GeometryNode):
    """
    Creates 3D extrusions of the footprint of each feature in the feature_list parameter of the constructor.
    """

    def __init__(self, feature_list, geometric_error=50):
        lod1_list = list()
        for feature in feature_list:
            extruded_polygon = ExtrudedPolygon(feature)
            lod1_list.append(extruded_polygon.get_extruded_object())
        super().__init__(feature_list=FeatureList(lod1_list), geometric_error=geometric_error)


class LoaNode(GeometryNode):
    """
    Creates 3D extrusions of the polygons given as parameter.
    The LoaNode also takes a dictionary stocking the indexes of the features contained in each polygon.
    """
    loa_index = 0

    def __init__(self, feature_list, geometric_error=50, additional_points=list(), points_dict=dict()):
        loas = list()
        for key in points_dict:
            contained_objects = FeatureList([feature_list[i] for i in points_dict[key]])
            loa = self.create_loa_from_polygon(contained_objects, additional_points[key], LoaNode.loa_index)
            loas.append(loa)
            LoaNode.loa_index += 1
        super().__init__(feature_list=FeatureList(loas), geometric_error=geometric_error)

    def create_loa_from_polygon(self, feature_list, polygon_points, index=0):
        """
        Create a LOA (3D extrusion of a polygon). The LOA is a 3D geometry containing a group of features.
        :param feature_list: the features contained in the LOA
        :param polygon_points: a polygon as list of 3D points
        :param int index: an index used for the LOA identifier

        :return: a 3D extrusion of the polygon
        """
        loa_geometry = Feature("loa_" + str(index))
        for feature in feature_list:
            loa_geometry.geom.triangles.append(feature.geom.triangles[0])

        extruded_polygon = ExtrudedPolygon(loa_geometry, override_points=True, polygon=polygon_points)
        return extruded_polygon.get_extruded_object()
