from ..Common import GeometryNode, GeometryTree
from .tile_to_object_to_tile import TilesToObjectsToTile


class TilesetTree(GeometryTree):

    def __init__(self, tileset, tileset_paths):
        self.tile_index = 0
        self.leaf_nodes = list()
        root_tile = tileset.get_root_tile()

        self.root_nodes = list()
        for i, tile in enumerate(root_tile.attributes['children']):
            offset = [c * -1 for c in tile.get_transform()[12:15]]
            self.root_nodes.append(self.tile_to_node(tile, tileset_paths[i], offset))

        centroid = self.get_root_objects().get_centroid()
        self.set_centroid(centroid)

    def tile_to_node(self, tile, tileset_path, offset):
        """
        Create a GeometryNode from a tile.
        :param tile: the tile to convert to node
        :param tileset_path: the path of the original tileset of the tile
        :param offset: the offset used to translate the geometries of this tile

        :return: a GeometryNode
        """
        geometric_error = tile.attributes["geometricError"]
        objects_to_tile = TilesToObjectsToTile(tile, tileset_path)
        objects_to_tile.translate_objects(offset)
        node = GeometryNode(objects_to_tile, geometric_error, with_texture=True)

        if 'children' in tile.attributes and len(tile.attributes['children']) > 0:
            for child in tile.attributes['children']:
                node.add_child_node(self.tile_to_node(child, tileset_path, offset))
        else:
            self.leaf_nodes.append(node)

        return node
