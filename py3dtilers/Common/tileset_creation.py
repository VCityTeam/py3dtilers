import numpy as np
from py3dtiles import B3dm, BatchTable, BoundingVolumeBox, GlTF, GlTFMaterial
from py3dtiles import Tile, TileSet
from ..Texture import Atlas


def create_tileset(geometry_tree, extension_name=None):
    """
    Recursively creates a tileset from the nodes of a LodTree
    :param objects_to_tile: an instance of ObjectsToTile containing a list of geometries to transform into 3DTiles
    """
    tileset = TileSet()
    centroid = geometry_tree.centroid
    for root_node in geometry_tree.root_nodes:
        create_tile(root_node, tileset, centroid, centroid, 0, extension_name)

    tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
    return tileset


def create_tile(node, parent, centroid, transform_offset, depth, extension_name=None):
    objects = node.objects_to_tile
    objects.translate_objects(centroid)

    tile = Tile()
    tile.set_geometric_error(node.geometric_error)

    content_b3dm = create_tile_content(objects, extension_name, node.has_texture())
    tile.set_content(content_b3dm)

    # Set the position of the tile. The position is relative to the parent tile's position
    tile.set_transform([1, 0, 0, 0,
                        0, 1, 0, 0,
                        0, 0, 1, 0,
                        transform_offset[0], transform_offset[1], transform_offset[2], 1])
    tile.set_refine_mode('REPLACE')
    bounding_box = BoundingVolumeBox()
    for feature in objects:
        bounding_box.add(feature.get_bounding_volume_box())

    if extension_name is not None:
        extension = objects.__class__.create_bounding_volume_extension(extension_name, None, objects)
        if extension is not None:
            bounding_box.add_extension(extension)

    tile.set_bounding_volume(bounding_box)

    # If the node is a root of the LodTree, add the created tile to the tileset's root
    if depth == 0:
        parent.add_tile(tile)
    # Else, add the created tile to its parent's children
    else:
        parent.add_child(tile)

    for child_node in node.child_nodes:
        create_tile(child_node, tile, centroid, [0., 0., 0.], depth + 1, extension_name)


def create_tile_content(objects, extension_name=None, with_texture=False):
    """
    :param pre_tile: an array containing features of a single tile

    :return: a B3dm tile.
    """
    # create B3DM content
    arrays = []
    materials = []
    seen_mat_indexes = []
    if with_texture:
        tile_atlas = Atlas(objects)
        objects.set_materials([GlTFMaterial(textureUri='./ATLAS_' + str(tile_atlas.tile_number) + '.png')])
    for feature in objects:
        mat_index = feature.material_index
        if mat_index not in seen_mat_indexes:
            seen_mat_indexes.append(mat_index)
            materials.append(objects.get_material(mat_index))
        content = {
            'position': feature.geom.getPositionArray(),
            'normal': feature.geom.getNormalArray(),
            'bbox': [[float(i) for i in j] for j in feature.geom.getBbox()],
            'matIndex': mat_index
        }
        if with_texture:
            content['uv'] = feature.geom.getDataArray(0)
        arrays.append(content)

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

    batched = len(materials) <= 1
    gltf = GlTF.from_binary_arrays(arrays, transform, batched=batched, materials=materials)

    # Create a batch table and add the ID of each feature to it
    ids = [feature.get_id() for feature in objects]
    bt = BatchTable()
    bt.add_property_from_array("id", ids)

    # if there is application specific data associated with the features, add it to the batch table
    features_data = [feature.get_batchtable_data() for feature in objects]
    if not all([feature_data is None for feature_data in features_data]):
        # Construct a set of all possible batch table keys
        bt_keys = set()
        for key_subset in [feature_data.keys() for feature_data in features_data]:
            bt_keys = bt_keys.union(set(key_subset))
        # add feature data to batch table based on possible keys
        for key in bt_keys:
            key_data = [feature_data.get(key, None) for feature_data in features_data]
            bt.add_property_from_array(key, key_data)

    if extension_name is not None:
        extension = objects.__class__.create_batch_table_extension(extension_name, ids, objects)
        if extension is not None:
            bt.add_extension(extension)

    # Eventually wrap the geometries together with the optional
    # BatchTableHierarchy within a B3dm:
    return B3dm.from_glTF(gltf, bt)
