from ..Common import GeometryNode
from ..Common import Lod1FeatureList, LoaFeatureList


class Lod1Node(GeometryNode):
    """
    Creates 3D extrusions of the footprint of each feature in the feature_list parameter of the constructor.
    """

    def __init__(self, features_node, geometric_error=50):
        feature_list = Lod1FeatureList(features_node=features_node)
        super().__init__(feature_list, geometric_error=geometric_error)


class LoaNode(GeometryNode):
    """
    Creates 3D extrusions of the polygons given as parameter.
    The LoaNode also takes a dictionary stocking the indexes of the features contained in each polygon.
    """

    def __init__(self, features_node, geometric_error=50, additional_points=list(), points_dict=dict()):
        feature_list = LoaFeatureList(points_dict=points_dict, additional_points=additional_points, features_node=features_node)
        super().__init__(feature_list, geometric_error=geometric_error)
