from ..Common import FeatureList
from typing import TYPE_CHECKING, List

if TYPE_CHECKING:
    from ..Common import GeometryNode


class GeometryTree():
    """
    The GeometryTree contains a list of GeometryNode instances.
    Those instances are the root nodes of a tree.
    The GeometryTree also contains the centroid of the root nodes.
    """

    def __init__(self, root_nodes: List['GeometryNode']):
        self.root_nodes = root_nodes

    def get_centroid(self):
        """
        Return the centroid of the tree.
        The centroid of the tree is the centroid of the leaf nodes features.
        """
        return self.get_leaf_objects().get_centroid()

    def get_leaf_nodes(self):
        """
        Return the leaf nodes of the tree.
        :return: a list of GeometryNode
        """
        leaf_nodes = list()
        for node in self.root_nodes:
            leaf_nodes.extend(node.get_leaves())
        return leaf_nodes

    def get_root_objects(self):
        """
        Return the features of the root nodes.
        :return: a FeatureList
        """
        return FeatureList([node.feature_list for node in self.root_nodes])

    def get_leaf_objects(self):
        """
        Return the features of the leaf nodes.
        :return: a FeatureList
        """
        return FeatureList([node.feature_list for node in self.get_leaf_nodes()])

    def get_all_objects(self):
        """
        Return the features of all the nodes.
        :return: a FeatureList
        """
        objects = list()
        for node in self.root_nodes:
            objects.extend(node.get_features())
        return FeatureList(objects)

    def get_number_of_nodes(self):
        """
        Return the number of nodes in the tree.
        :return: int
        """
        n = len(self.root_nodes)
        for node in self.root_nodes:
            n += node.get_number_of_children()
        return n
