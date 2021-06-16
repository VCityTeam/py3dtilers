import numpy as np
from py3dtiles import B3dm, BatchTable, BoundingVolumeBox, GlTF
from py3dtiles import Tile, TileSet
from ..Common import ObjectsToTile
from ..Common import get_lod1

# Each node contains a collection of objects to tile
# and a list of nodes
# A node will correspond to a tile of the 3dtiles tileset


class LodNode():

    def __init__(self, objects_to_tile=None, depth=0):
        self.objects_to_tile = objects_to_tile
        self.child_nodes = list()
        self.depth = depth

    def set_child_nodes(self, nodes=list()):
        self.child_nodes = nodes
    
    def add_child_node(self, node):
        self.child_nodes.append(node)

# The LodTree contains the root node(s) of the LOD hierarchy


class LodTree():
    def __init__(self, root_nodes=list()):
        self.root_nodes = root_nodes
        self.centroid = [0., 0., 0.]
        self.depth = 0
        if len(root_nodes) > 0:
            self.depth = root_nodes[0].depth

    def set_centroid(self, centroid):
        self.centroid = centroid

class LoaDict():
    def __init__(self):
        self.dict = {}
        self.objects_to_tile = list()

def create_lod_tree(objects_to_tile, also_create_lod1=True, also_create_loa=True):
    nodes = list()
    if also_create_loa:
        loa = create_loa(objects_to_tile)
        seen_loa = list()
        loa_nodes = {}
    for i, object_to_tile in enumerate(objects_to_tile):
        depth = 0
        add_root_node = True
        node = LodNode(ObjectsToTile([object_to_tile]),depth)
        root_node = node
        if also_create_lod1:
            depth += 1
            lod1_node = LodNode(ObjectsToTile([get_lod1(object_to_tile)]),depth)
            lod1_node.add_child_node(node)
            root_node = lod1_node
        if also_create_loa:
            depth += 1
            corresponding_loa = loa.dict[i]
            if not corresponding_loa in seen_loa:
                loa_node = LodNode(ObjectsToTile([loa.objects_to_tile[corresponding_loa]]),depth)
                loa_nodes[corresponding_loa] = loa_node
            else:
                loa_node = loa_nodes[corresponding_loa]
                add_root_node = False
            loa_node.add_child_node(root_node)
            root_node = loa_node

        if add_root_node: 
            nodes.append(root_node)

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


def create_tile(node, parent, centroid, transform_offset, root_depth):
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

    if not node.depth == root_depth:
        parent.add_child(tile)
    else:
        parent.add_tile(tile)

    for child_node in node.child_nodes:
        create_tile(child_node, tile, centroid, [0., 0., 0.], root_depth)


def create_tileset(lod_tree):
    
    tileset = TileSet()
    centroid = lod_tree.centroid
    root_depth = lod_tree.depth
    for root_node in lod_tree.root_nodes:
        create_tile(root_node, tileset, centroid, centroid, root_depth)

    return tileset

def create_loa(objects_to_tile):
    loa = LoaDict()
    for i, object_to_tile in enumerate(objects_to_tile):
        loa.objects_to_tile.append(object_to_tile)
        loa.dict[i] = i
    return loa