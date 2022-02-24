from ..Common import GeometryTree, GeometryNode, Lod1Node, LoaNode, Groups


class LodTree(GeometryTree):
    """
    The LodTree contains the root node(s) of the LOD hierarchy and the centroid of the whole tileset
    """

    def __init__(self, feature_list, create_lod1=False, create_loa=False, polygons_path=None, with_texture=False):
        """
        LodTree takes an instance of FeatureList (which contains a collection of Feature) and creates nodes.
        In order to reduce the number of .b3dm, it also distributes the features into a list of Group.
        A Group contains features and an optional polygon that will be used for LoaNodes.
        """
        root_nodes = list()

        groups = self.group_features(feature_list, polygons_path)

        for group in groups:
            node = GeometryNode(group.feature_list, 1, with_texture)
            root_node = node
            if create_lod1:
                lod1_node = Lod1Node(node, 5)
                lod1_node.add_child_node(root_node)
                root_node = lod1_node
            if group.with_polygon:
                loa_node = LoaNode(node, 20, group.additional_points, group.points_dict)
                loa_node.add_child_node(root_node)
                root_node = loa_node

            root_nodes.append(root_node)

        super().__init__(root_nodes)

    def group_features(self, feature_list, polygons_path=None):
        """
        Distribute feature_list into groups to reduce the number of tiles.
        :param feature_list: a FeatureList to distribute into groups.
        :param polygons_path: a path to the file(s) containing polygons (used for LOA creation)

        :return: a list of groups, each group containing features
        """
        groups = Groups(feature_list, polygons_path)
        return groups.get_groups_as_list()
