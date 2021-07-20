from ..Common import ObjectsToTile, ObjectsToTileWithGeometry
from ..Common import kd_tree
from ..Common import get_lod1
from ..Common import create_loa


class LodNode():
    """
    Each node contains a collection of objects to tile
    and a list of child nodes
    A node will correspond to a tile of the 3dtiles tileset
    """

    def __init__(self, objects_to_tile=None, geometric_error=50):
        self.objects_to_tile = objects_to_tile
        self.child_nodes = list()
        self.geometric_error = geometric_error
        self.with_texture = False

    def set_child_nodes(self, nodes=list()):
        self.child_nodes = nodes

    def add_child_node(self, node):
        self.child_nodes.append(node)

    def has_texture(self):
        return self.with_texture


class LodTree():
    """
    The LodTree contains the root node(s) of the LOD hierarchy and the centroid of the whole tileset
    """
    def __init__(self, root_nodes=list()):
        self.root_nodes = root_nodes
        self.centroid = [0., 0., 0.]

    def set_centroid(self, centroid):
        self.centroid = centroid


def create_lod_tree(objects_to_tile, also_create_lod1=False, also_create_loa=False, loa_path=None, with_texture=False):
    """
    create_lod_tree takes an instance of ObjectsToTile (which contains a collection of ObjectToTile) and creates nodes
    In order to reduce the number of .b3dm, it also groups the objects (ObjectToTile instances) in different ObjectsToTileWithGeometry
    An ObjectsToTileWithGeometry contains an ObjectsToTile (the ObjectToTile(s) in the group) and an optional ObjectsToTile which is its own geometry
    """
    root_nodes = list()

    groups = group_features(objects_to_tile, also_create_loa, loa_path)

    for group in groups:
        node = LodNode(group.objects_to_tile, 1)
        node.with_texture = with_texture
        root_node = node
        if also_create_lod1:
            lod1_node = LodNode(ObjectsToTile([get_lod1(object_to_tile) for object_to_tile in group.objects_to_tile]), 5)
            lod1_node.add_child_node(root_node)
            root_node = lod1_node
        if group.with_geometry:
            loa_node = LodNode(group.geometry, 20)
            loa_node.add_child_node(root_node)
            root_node = loa_node

        root_nodes.append(root_node)

    tree = LodTree(root_nodes)
    tree.set_centroid(objects_to_tile.get_centroid())
    return tree


def group_features(objects_to_tile, also_create_loa=False, loa_path=None):
    """
    Group objects_to_tile to reduce the number of tiles
    """
    groups = list()
    if also_create_loa:
        groups = create_loa(objects_to_tile, loa_path)
    else:
        objects = kd_tree(objects_to_tile, 500)
        for objects_to_tile in objects:
            group = ObjectsToTileWithGeometry(objects_to_tile)
            groups.append(group)
    return groups
