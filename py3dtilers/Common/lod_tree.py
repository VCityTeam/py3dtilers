import numpy as np
from py3dtiles import B3dm, BatchTable, BoundingVolumeBox, GlTF
from py3dtiles import Tile, TileSet
from ..Common import ObjectsToTile, ObjectsToTileWithGeometry
from ..Common import kd_tree
from ..Common import get_lod1
from ..Common import create_loa

# Each node contains a collection of objects to tile
# and a list of nodes
# A node will correspond to a tile of the 3dtiles tileset


class LodNode():

    def __init__(self, objects_to_tile=None, geometric_error=50):
        self.objects_to_tile = objects_to_tile
        self.child_nodes = list()
        self.geometric_error = geometric_error

    def set_child_nodes(self, nodes=list()):
        self.child_nodes = nodes
    
    def add_child_node(self, node):
        self.child_nodes.append(node)

# The LodTree contains the root node(s) of the LOD hierarchy


class LodTree():
    def __init__(self, root_nodes=list()):
        self.root_nodes = root_nodes
        self.centroid = [0., 0., 0.]

    def set_centroid(self, centroid):
        self.centroid = centroid

# create_lod_tree takes an instance of ObjectsToTile (which contains a collection of ObjectToTile) and creates nodes
# In order to reduce the number of .b3dm, it also groups the objects (ObjectToTile instances) in different ObjectsToTileWithGeometry
# An ObjectsToTileWithGeometry contains an ObjectsToTile (the ObjectToTile(s) in the group) and an optional ObjectToTile which is its own geometry
def create_lod_tree(objects_to_tile, also_create_lod1=False, also_create_loa=False, loa_path=None):
    nodes = list()

    groups = group_features(objects_to_tile, also_create_loa, loa_path)
    #groups = group_features_by_cube(groups, 1000)

    for group in groups:
        node = LodNode(group.objects_to_tile,1)
        root_node = node
        if also_create_lod1:
            lod1_node = LodNode(ObjectsToTile([get_lod1(object_to_tile) for object_to_tile in group.objects_to_tile]),5)
            lod1_node.add_child_node(root_node)
            root_node = lod1_node
        if group.with_geometry:
            loa_node = LodNode(ObjectsToTile([group.geometry]),20)
            loa_node.add_child_node(root_node)
            root_node = loa_node

        nodes.append(root_node)

    tree = LodTree(nodes)
    tree.set_centroid(objects_to_tile.get_centroid())
    return tree


def create_tileset(objects_to_tile, also_create_lod1=False, also_create_loa=False, loa_path=None):
    lod_tree = create_lod_tree(objects_to_tile, also_create_lod1, also_create_loa, loa_path)

    tileset = TileSet()
    centroid = lod_tree.centroid
    for root_node in lod_tree.root_nodes:
        create_tile(root_node, tileset, centroid, centroid, 0)

    return tileset


def create_tile(node, parent, centroid, transform_offset, depth):
    objects = node.objects_to_tile
    objects.translate_tileset(centroid)

    tile = Tile()
    tile.set_geometric_error(node.geometric_error)

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

    if depth == 0:
        parent.add_tile(tile)
    else:
        parent.add_child(tile)

    for child_node in node.child_nodes:
        create_tile(child_node, tile, centroid, [0., 0., 0.], depth + 1)


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


def group_features(objects_to_tile,also_create_loa=False, loa_path=None):
    groups = list()
    if also_create_loa:
        groups = create_loa(objects_to_tile, loa_path)
    else:
        objects = kd_tree(objects_to_tile, 100)
        for objects_to_tile in objects:
            group = ObjectsToTileWithGeometry(objects_to_tile)
            groups.append(group)
    return groups
