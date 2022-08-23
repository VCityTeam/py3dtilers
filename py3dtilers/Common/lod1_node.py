from ..Common import GeometryNode
from ..Common import Lod1FeatureList


class Lod1Node(GeometryNode):
    """
    Creates 3D extrusions of the footprint of each feature in the feature_list parameter of the constructor.
    """

    DEFAULT_GEOMETRIC_ERROR = 5

    def __init__(self, features_node: GeometryNode, geometric_error=None):
        feature_list = Lod1FeatureList(features_node=features_node)
        super().__init__(feature_list, geometric_error=geometric_error)
