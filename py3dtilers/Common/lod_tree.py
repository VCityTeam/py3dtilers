from ..Common import LodNode, Lod1Node, LoaNode, Groups


class LodTree():
    """
    The LodTree contains the root node(s) of the LOD hierarchy and the centroid of the whole tileset
    """

    def __init__(self, objects_to_tile, create_lod1=False, create_loa=False, polygons_path=None, with_texture=False):
        """
        create_lod_tree takes an instance of ObjectsToTile (which contains a collection of ObjectToTile) and creates nodes.
        In order to reduce the number of .b3dm, it also distributes the geometries into a list of Group.
        A Group contains geometries and an optional polygon that will be used for LoaNodes.
        """
        root_nodes = list()

        groups = self.group_features(objects_to_tile, polygons_path)

        for group in groups:
            node = LodNode(group.objects_to_tile, 1)
            node.with_texture = with_texture
            root_node = node
            if create_lod1:
                lod1_node = Lod1Node(group.objects_to_tile, 5)
                lod1_node.add_child_node(root_node)
                root_node = lod1_node
            if group.with_polygon:
                loa_node = LoaNode(group.objects_to_tile, 20, group.additional_points, group.points_dict)
                loa_node.add_child_node(root_node)
                root_node = loa_node

            root_nodes.append(root_node)

        self.root_nodes = root_nodes
        self.centroid = objects_to_tile.get_centroid()

    def set_centroid(self, centroid):
        """
        Set the centroid of the tree.
        :param centroid: the centroid
        """
        self.centroid = centroid

    def group_features(self, objects_to_tile, polygons_path=None):
        """
        Distribute objects_to_tile into groups to reduce the number of tiles.
        :param objects_to_tile: a list of geometries to distribute into groups.
        :param polygons_path: a path to the file(s) containing polygons (used for LOA creation)

        :return: a list of groups, each group containing geometries
        """
        groups = Groups(objects_to_tile, polygons_path)
        return groups.get_groups_as_list()
