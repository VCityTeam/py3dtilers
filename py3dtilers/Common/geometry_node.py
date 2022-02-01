class GeometryNode():
    """
    Each node contains an instance of ObjectsToTile
    and a list of child nodes
    A node will correspond to a tile of the 3dtiles tileset
    """

    def __init__(self, objects_to_tile=None, geometric_error=50, with_texture=False):
        """
        :param objects_to_tile: an instance of ObjectsToTile.
        :param geometric_error: the distance below which this node should be displayed.
        :param Boolean with_texture: if this node must keep the texture of the geometries or not.
        """
        self.objects_to_tile = objects_to_tile
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
        Return True if this node must keep the texture of its geometries.
        :return: boolean
        """
        return self.with_texture

    def geometries_have_texture(self):
        """
        Check if all the geometries in the node have a texture.
        :return: a boolean
        """
        return all([feature.has_texture() for feature in self.objects_to_tile])

    def get_objects(self):
        """
        Return the geometries in this node and the geometries in the child nodes (recursively).
        :return: a list of geometries
        """
        objects = [self.objects_to_tile]
        for child in self.child_nodes:
            objects.extend(child.get_objects())
        return objects
