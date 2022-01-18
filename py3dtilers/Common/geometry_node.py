class GeometryNode():
    """
    Each node contains a collection of objects to tile
    and a list of child nodes
    A node will correspond to a tile of the 3dtiles tileset
    """

    def __init__(self, objects_to_tile=None, with_texture=False):
        """
        :param objects_to_tile: an instance ObjectsToTile containing the list of geometries contained in the node
        :param geometric_error: the distance to display the 3D tile that will be created from this node.
        """
        self.objects_to_tile = objects_to_tile
        self.child_nodes = list()
        self.with_texture = with_texture and self.geometries_have_texture()

    def set_child_nodes(self, nodes=list()):
        self.child_nodes = nodes

    def add_child_node(self, node):
        self.child_nodes.append(node)

    def has_texture(self):
        return self.with_texture

    def geometries_have_texture(self):
        """
        Check if all the geometries in the node have a texture.
        :return: a boolean
        """
        return all([feature.has_texture() for feature in self.objects_to_tile])
