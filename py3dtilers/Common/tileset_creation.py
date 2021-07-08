import numpy as np
from py3dtiles import B3dm, BatchTable, BoundingVolumeBox, GlTF
from py3dtiles import Tile, TileSet
from ..Common import create_lod_tree


def create_tileset(objects_to_tile, also_create_lod1=False, also_create_loa=False, loa_path=None, extension_name=None):
    """
    Recursively creates a tileset from the nodes of a LodTree
    """
    lod_tree = create_lod_tree(objects_to_tile, also_create_lod1, also_create_loa, loa_path)

    tileset = TileSet()
    centroid = lod_tree.centroid
    for root_node in lod_tree.root_nodes:
        create_tile(root_node, tileset, centroid, centroid, 0, extension_name)

    return tileset


def create_tile(node, parent, centroid, transform_offset, depth, extension_name=None):
    objects = node.objects_to_tile
    objects.translate_tileset(centroid)

    tile = Tile()
    tile.set_geometric_error(node.geometric_error)

    content_b3dm = create_tile_content(objects, extension_name)
    tile.set_content(content_b3dm)

    # Set the position of the tile. The position is relative to the parent tile's position
    tile.set_transform([1, 0, 0, 0,
                        0, 1, 0, 0,
                        0, 0, 1, 0,
                        transform_offset[0], transform_offset[1], transform_offset[2], 1])
    tile.set_refine_mode('REPLACE')
    bounding_box = BoundingVolumeBox()
    for geojson in objects:
        bounding_box.add(geojson.get_bounding_volume_box())
    tile.set_bounding_volume(bounding_box)

    # If the node is a root of the LodTree, add the created tile to the tileset's root
    if depth == 0:
        parent.add_tile(tile)
    # Else, add the created tile to its parent's children
    else:
        parent.add_child(tile)

    for child_node in node.child_nodes:
        create_tile(child_node, tile, centroid, [0., 0., 0.], depth + 1, extension_name)


def create_tile_content(pre_tile, extension_name=None):
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

    if extension_name is not None:
        extension = pre_tile.__class__.create_extension(extension_name, ids)
        if extension is not None:
            bt.add_extension(extension)

    # Eventually wrap the geometries together with the optional
    # BatchTableHierarchy within a B3dm:
    return B3dm.from_glTF(gltf, bt)