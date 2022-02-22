class GeometryNode():
    """
    Each node contains an instance of FeatureList
    and a list of child nodes
    A node will correspond to a tile of the 3dtiles tileset
    """

    def __init__(self, feature_list=None, geometric_error=50, with_texture=False):
        """
        :param feature_list: an instance of FeatureList.
        :param geometric_error: the distance below which this node should be displayed.
        :param Boolean with_texture: if this node must keep the texture of the features or not.
        """
        self.feature_list = feature_list
        self.child_nodes = list()
        self.with_texture = with_texture and self.geometries_have_texture()
        self.geometric_error = geometric_error

    def set_child_nodes(self, nodes=list()):
        """
        Set the child nodes of this node.
        :param nodes: list of nodes
        """
        self.child_nodes = nodes

    def add_child_node(self, node):
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
        return self.with_texture

    def geometries_have_texture(self):
        """
        Check if all the features in the node have a texture.
        :return: a boolean
        """
        return all([feature.has_texture() for feature in self.feature_list])

    def get_objects(self):
        """
        Return the features in this node and the features in the child nodes (recursively).
        :return: a FeatureList
        """
        objects = [self.feature_list]
        for child in self.child_nodes:
            objects.extend(child.get_objects())
        return objects

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
