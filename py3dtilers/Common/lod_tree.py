from ..Common import GeometryTree, GeometryNode, Lod1Node, LoaNode
from typing import TYPE_CHECKING
import copy

if TYPE_CHECKING:
    from ..Common import Groups


class LodTree(GeometryTree):
    """
    The LodTree contains the root node(s) of the LOD hierarchy and the centroid of the whole tileset
    """

    def __init__(self, groups: 'Groups', create_lod1=False, create_loa=False, with_texture=False, geometric_errors=[None, None, None], texture_lods=0):
        """
        LodTree takes an instance of FeatureList (which contains a collection of Feature) and creates nodes.
        In order to reduce the number of .b3dm, it also distributes the features into a list of Group.
        A Group contains features and an optional polygon that will be used for LoaNodes.
        """
        root_nodes = list()

        for group in groups:
            node = GeometryNode(group.feature_list, geometric_errors[0], with_texture)
            root_node = node
            downsample_factor = 3
            for _ in range(0, texture_lods):
                geometric_error = (downsample_factor / 3) + geometric_errors[0] if geometric_errors[0] else downsample_factor / 3
                textured_node = GeometryNode(copy.deepcopy(group.feature_list), geometric_error, with_texture, downsample_factor)
                textured_node.add_child_node(root_node)
                root_node = textured_node
                downsample_factor += 10
            if create_lod1:
                lod1_node = Lod1Node(node, geometric_errors[1])
                lod1_node.add_child_node(root_node)
                root_node = lod1_node
            if create_loa:
                loa_node = LoaNode(node, geometric_errors[2], group.polygons)
                loa_node.add_child_node(root_node)
                root_node = loa_node

            root_nodes.append(root_node)

        super().__init__(root_nodes)

    @staticmethod
    def vertical_hierarchy(groups: 'Groups', geometric_errors=[None]):
        root_node = GeometryNode(groups[0].feature_list, geometric_errors[0])
        for i in range(1, len(groups)):
            geometric_error = geometric_errors[i] if i < len(geometric_errors) else None
            node = GeometryNode(groups[i].feature_list, geometric_error)
            node.add_child_node(root_node)
            root_node = node
        tree = GeometryTree([root_node])
        return tree
