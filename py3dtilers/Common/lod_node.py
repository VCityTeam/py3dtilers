from ..Common import ObjectsToTile, ObjectToTile
from ..Common import ExtrudedPolygon


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


class Lod1Node(LodNode):
    def __init__(self, objects_to_tile, geometric_error=50):
        lod1_objects_to_tile = ObjectsToTile([ExtrudedPolygon.create_footprint_extrusion(object_to_tile) for object_to_tile in objects_to_tile])
        super().__init__(objects_to_tile=lod1_objects_to_tile, geometric_error=geometric_error)


class LoaNode(LodNode):

    loa_index = 0

    def __init__(self, objects_to_tile, geometric_error=50, additional_points=list(), points_dict=dict()):
        loas = list()
        for key in points_dict:
            contained_objects = ObjectsToTile([objects_to_tile[i] for i in points_dict[key]])
            loa = self.create_loa_from_polygon(contained_objects, additional_points[key], LoaNode.loa_index)
            loas.append(loa)
            LoaNode.loa_index += 1
        super().__init__(objects_to_tile=ObjectsToTile(loas), geometric_error=geometric_error)

    def create_loa_from_polygon(self, objects_to_tile, polygon_points, index=0):
        loa_geometry = ObjectToTile("loa_" + str(index))
        for object_to_tile in objects_to_tile:
            loa_geometry.geom.triangles.append(object_to_tile.geom.triangles[0])
        loa_geometry = ExtrudedPolygon.create_footprint_extrusion(loa_geometry, override_points=True, polygon=polygon_points)
        return loa_geometry
