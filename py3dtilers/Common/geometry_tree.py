from ..Common import FeatureList


class GeometryTree():
    """
    The GeometryTree contains the root nodes and the leaf nodes of the hierarchy.
    It also contains the centroid of the root nodes.
    """

    def __init__(self, root_nodes):
        self.root_nodes = root_nodes

    def get_centroid(self):
        """
        Return the centroid of the tree.
        The centroid of the tree is the centroid of the root nodes features.
        """
        return self.get_root_objects().get_centroid()

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
        Return the geometries of the root nodes.
        :return: list of geometries
        """
        return FeatureList([node.feature_list for node in self.root_nodes])

    def get_leaf_objects(self):
        """
        Return the geometries of the leaf nodes.
        :return: list of geometries
        """
        return FeatureList([node.feature_list for node in self.get_leaf_nodes()])

    def get_all_objects(self):
        """
        Return the geometries of all the nodes.
        :return: list of geometries
        """
        objects = list()
        for node in self.root_nodes:
            objects.extend(node.get_objects())
        return FeatureList(objects)
