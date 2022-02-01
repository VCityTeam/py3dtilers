from ..Common import GeometryNode, GeometryTree


class TilesetTree(GeometryTree):

    def __init__(self, tileset, objects):
        self.tile_index = 0
        self.leaf_nodes = list()
        root_tile = tileset.get_root_tile()

        self.root_nodes = list()
        for tile in root_tile.attributes['children']:
            offset = [c * -1 for c in tile.get_transform()[12:15]]
            self.root_nodes.append(self.tile_to_node(tile, objects, offset))

        centroid = self.get_root_objects().get_centroid()
        self.set_centroid(centroid)

    def get_next_tile_index(self):
        """
        Get the next tile index.
        :return: an index
        """
        index = self.tile_index
        self.tile_index += 1
        return index

    def tile_to_node(self, tile, objects, offset):
        """
        Create a GeometryNode from a tile.
        :param tile: the tile to parse
        :param objects: the list which contains all the geometries of the tree
        :param offset: the offset used to translate the geometries of this tile

        :return: a GeometryNode
        """
        id = self.get_next_tile_index()
        geometric_error = tile.attributes["geometricError"]
        objects_to_tile = objects.parse_tile(tile, id)
        objects_to_tile.translate_objects(offset)
        objects.append(objects_to_tile)
        node = GeometryNode(objects_to_tile, geometric_error, with_texture=True)

        if 'children' in tile.attributes and len(tile.attributes['children']) > 0:
            for child in tile.attributes['children']:
                node.add_child_node(self.tile_to_node(child, objects, offset))
        else:
            self.leaf_nodes.append(node)

        return node
