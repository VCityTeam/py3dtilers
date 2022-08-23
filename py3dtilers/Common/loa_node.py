from ..Common import GeometryNode
from ..Common import LoaFeatureList


class LoaNode(GeometryNode):
    """
    Creates 3D extrusions of the polygons given as parameter.
    Only the polygons containing at least one feature are extruded.
    If a feature isn't contained in any polygon, create a 3D extrusion of its footprint.
    """

    DEFAULT_GEOMETRIC_ERROR = 20

    def __init__(self, features_node: GeometryNode, geometric_error=None, polygons=list()):
        feature_list = LoaFeatureList(polygons=polygons, features_node=features_node)
        super().__init__(feature_list, geometric_error=geometric_error)
