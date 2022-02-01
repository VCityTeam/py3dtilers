from ..Common import ObjectsToTile


class GeometryTree():
    """
    The GeometryTree contains the root nodes and the leaf nodes of the hierarchy.
    It also contains the centroid of the root nodes.
    """

    def __init__(self, objects_to_tile, root_nodes):
        self.root_nodes = root_nodes
        self.leaf_nodes = list()
        self.centroid = objects_to_tile.get_centroid()

    def set_centroid(self, centroid):
        self.centroid = centroid

    def get_root_objects(self):
        """
        Return the geometries of the root nodes.
        :return: list of geometries
        """
        return ObjectsToTile([node.objects_to_tile for node in self.root_nodes])

    def get_leaf_objects(self):
        """
        Return the geometries of the leaf nodes.
        :return: list of geometries
        """
        return ObjectsToTile([node.objects_to_tile for node in self.leaf_nodes])

    def get_all_objects(self):
        """
        Return the geometries of all the nodes.
        :return: list of geometries
        """
        objects = list()
        for node in self.root_nodes:
            objects.extend(node.get_objects())
        return ObjectsToTile(objects)
