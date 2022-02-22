from ..Common import GeometryNode, GeometryTree
from .tile_to_feature import TileToFeatureList


class TilesetTree(GeometryTree):

    def __init__(self, tileset, tileset_paths):
        self.tile_index = 0
        root_tile = tileset.get_root_tile()

        root_nodes = list()
        for i, tile in enumerate(root_tile.attributes['children']):
            offset = [c * -1 for c in tile.get_transform()[12:15]]
            root_nodes.append(self.tile_to_node(tile, tileset_paths[i], offset))

        super().__init__(root_nodes)

    def tile_to_node(self, tile, tileset_path, offset):
        """
        Create a GeometryNode from a tile.
        :param tile: the tile to convert to node
        :param tileset_path: the path of the original tileset of the tile
        :param offset: the offset used to translate the features of this tile

        :return: a GeometryNode
        """
        geometric_error = tile.attributes["geometricError"]
        feature_list = TileToFeatureList(tile, tileset_path)
        feature_list.translate_features(offset)
        node = GeometryNode(feature_list, geometric_error, with_texture=True)

        if 'children' in tile.attributes and len(tile.attributes['children']) > 0:
            for child in tile.attributes['children']:
                node.add_child_node(self.tile_to_node(child, tileset_path, offset))

        return node
