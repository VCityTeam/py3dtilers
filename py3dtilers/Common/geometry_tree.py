class GeometryTree():
    """
    The GeometryTree contains the root node(s) of the hierarchy and the centroid of the whole tileset
    """

    def __init__(self, objects_to_tile, root_nodes):
        self.root_nodes = root_nodes
        self.centroid = objects_to_tile.get_centroid()

    def set_centroid(self, centroid):
        self.centroid = centroid
