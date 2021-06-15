import numpy as np
from py3dtiles import B3dm, BatchTable, BoundingVolumeBox, GlTF
from py3dtiles import Tile, TileSet
from ..Common import ObjectsToTile

# Each node contains a collection of objects to tile
# and a list of nodes
# A node will correspond to a tile of the 3dtiles tileset


class LodNode():

    def __init__(self, objects_to_tile=None, depth=0):
        self.objects_to_tile = objects_to_tile
        self.child_nodes = list()
        self.depth = depth

    # Create child node(s) from a collection of objects to tile
    # Those objects can be in a single node (and then a single tile)
    # or in differents nodes (and thus different tiles)
    def set_child_nodes(self, objects_to_tile, group_children=True):
        if not group_children:
            for object_to_tile in objects_to_tile:
                self.child_nodes.append(LodNode(ObjectsToTile([object_to_tile]), self.depth + 1))

        else:
            self.child_nodes.append(LodNode(objects_to_tile, self.depth + 1))

# The LodTree contains the root node(s) of the LOD hierarchy


class LodTree():
    def __init__(self, root_nodes=list()):
        self.root_nodes = root_nodes
        self.centroid = [0., 0., 0.]

    def set_centroid(self, centroid):
        self.centroid = centroid


def create_lod_tree(objects_to_tile_array=list(), group=True):

    nodes = list()
    
    for objects_to_tile in objects_to_tile_array:
        if not group:
            for object_to_tile in objects_to_tile:
                nodes.append(LodNode(ObjectsToTile([object_to_tile])))
        else:
            nodes.append(LodNode(objects_to_tile))

    tree = LodTree(nodes)
    tree.set_centroid(objects_to_tile.get_centroid())
    return tree


def create_tile_content(pre_tile):
    """
    :param pre_tile: an array containing features of a single tile

    :return: a B3dm tile.
    """
    # create B3DM content
    arrays = []
    for feature in pre_tile:
        arrays.append({
            'position': feature.geom.getPositionArray(),
            'normal': feature.geom.getNormalArray(),
            'bbox': [[float(i) for i in j] for j in feature.geom.getBbox()]
        })

    # GlTF uses a y-up coordinate system whereas the geographical data (stored
    # in the 3DCityDB database) uses a z-up coordinate system convention. In
    # order to comply with Gltf we thus need to realize a z-up to y-up
    # coordinate transform for the data to respect the glTF convention. This
    # rotation gets "corrected" (taken care of) by the B3dm/gltf parser on the
    # client side when using (displaying) the data.
    # Refer to the note concerning the recommended data workflow
    # https://github.com/AnalyticalGraphicsInc/3d-tiles/tree/master/specification#gltf-transforms
    # for more details on this matter.
    transform = np.array([1, 0, 0, 0,
                          0, 0, -1, 0,
                          0, 1, 0, 0,
                          0, 0, 0, 1])
    gltf = GlTF.from_binary_arrays(arrays, transform)

    # Create a batch table and add the ID of each feature to it
    ids = [feature.get_id() for feature in pre_tile]
    bt = BatchTable()
    bt.add_property_from_array("id", ids)

    # Eventually wrap the geometries together with the optional
    # BatchTableHierarchy within a B3dm:
    return B3dm.from_glTF(gltf, bt)


def create_tile(node, parent, centroid, transform_offset):
    objects = node.objects_to_tile
    objects.translate_tileset(centroid)

    tile = Tile()
    tile.set_geometric_error(50)

    content_b3dm = create_tile_content(objects)
    tile.set_content(content_b3dm)
    tile.set_transform([1, 0, 0, 0,
                        0, 1, 0, 0,
                        0, 0, 1, 0,
                        transform_offset[0], transform_offset[1], transform_offset[2], 1])
    tile.set_refine_mode('REPLACE')
    bounding_box = BoundingVolumeBox()
    for geojson in objects:
        bounding_box.add(geojson.get_bounding_volume_box())
    tile.set_bounding_volume(bounding_box)

    if node.depth > 0:
        parent.add_child(tile)
    else:
        parent.add_tile(tile)

    for child_node in node.child_nodes:
        create_tile(child_node, tile, centroid, [0., 0., 0.])


def create_tileset(lod_tree):

    tileset = TileSet()
    centroid = lod_tree.centroid

    for root_node in lod_tree.root_nodes:
        create_tile(root_node, tileset, centroid, centroid)

    return tileset
