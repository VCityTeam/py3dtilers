from typing import TYPE_CHECKING, List

if TYPE_CHECKING:
    from ..Common import FeatureList


class GeometryNode():
    """
    Each node contains an instance of FeatureList
    and a list of child nodes.
    A node will correspond to a tile of the 3dtiles tileset.
    """

    # In 3D Tiles, the geometric error is the metric used to refine a tile.
    # The leaves of the tileset should have the lower geometric error.
    # https://github.com/CesiumGS/3d-tiles/tree/main/specification#geometric-error
    DEFAULT_GEOMETRIC_ERROR = 1

    def __init__(self, feature_list: 'FeatureList' = None, geometric_error=None, with_texture=False, downsample_factor=1):
        """
        :param feature_list: an instance of FeatureList.
        :param geometric_error: the metric used to refine the node when visualizing the features.
        :param Boolean with_texture: if this node must keep the texture of the features or not.
        :param int downsample_factor: the factor used to downsize the texture image
        """
        self.feature_list = feature_list
        self.child_nodes = list()
        self.with_texture = with_texture
        self.geometric_error = geometric_error if geometric_error is not None else self.DEFAULT_GEOMETRIC_ERROR
        self.downsample_factor = downsample_factor

    def set_child_nodes(self, nodes: List['GeometryNode'] = list()):
        """
        Set the child nodes of this node.
        :param nodes: list of nodes
        """
        self.child_nodes = nodes

    def add_child_node(self, node: 'GeometryNode'):
        """
        Add a child to the child nodes.
        :param node: a node
        """
        self.child_nodes.append(node)

    def has_texture(self):
        """
        Return True if this node must keep the texture of its features.
        :return: boolean
        """
        return self.with_texture and self.geometries_have_texture()

    def geometries_have_texture(self):
        """
        Check if all the features in the node have a texture.
        :return: a boolean
        """
        return all([feature.has_texture() for feature in self.feature_list])

    def get_features(self):
        """
        Return the features in this node and the features in the child nodes (recursively).
        :return: a list of Feature
        """
        features = [self.feature_list]
        for child in self.child_nodes:
            features.extend(child.get_features())
        return features

    def set_node_features_geometry(self, user_arguments=None):
        """
        Set the geometry of the features in this node and the features in the child nodes (recursively).
        """
        for features in reversed(self.get_features()):
            features.set_features_geom(user_arguments)

    def get_leaves(self):
        """
        Return the leaves of this node.
        If the node has no child, return this node.
        :return: a list of GeometryNode
        """
        if len(self.child_nodes) < 1:
            return [self]
        else:
            leaves = list()
            for node in self.child_nodes:
                leaves.extend(node.get_leaves())
            return leaves

    def get_number_of_children(self):
        """
        Return the number of children of this node.
        The count is recursive.
        :return: int
        """
        n = len(self.child_nodes)
        for child in self.child_nodes:
            n += child.get_number_of_children()
        return n
