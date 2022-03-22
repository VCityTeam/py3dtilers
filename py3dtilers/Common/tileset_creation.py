import numpy as np
import os
from pyproj import Transformer
from py3dtiles import B3dm, BatchTable, BoundingVolumeBox, GlTF, GlTFMaterial
from py3dtiles import Tile, TileSet
from ..Texture import Atlas
from ..Common import ObjWriter


class FromGeometryTreeToTileset():
    """
    A static class to create a 3DTiles tileset from a GeometryTree.
    """

    tile_index = 0
    nb_nodes = 0

    @staticmethod
    def convert_to_tileset(geometry_tree, user_arguments=None, extension_name=None, output_dir=None):
        """
        Recursively creates a tileset from the nodes of a GeometryTree
        :param geometry_tree: an instance of GeometryTree to transform into 3DTiles.
        :param user_arguments: the Namespace containing the arguments of the command line.
        :param extension_name: the name of an extension to add to the tileset.
        :param output_dir: the directory where the TileSet is writen.

        :return: a TileSet
        """
        print('Creating tileset from features...')
        tileset = TileSet()
        FromGeometryTreeToTileset.nb_nodes = geometry_tree.get_number_of_nodes()
        obj_writer = ObjWriter()
        while len(geometry_tree.root_nodes) > 0:
            root_node = geometry_tree.root_nodes[0]
            root_node.set_node_features_geometry(user_arguments)
            FromGeometryTreeToTileset.__transform_node(root_node, user_arguments, obj_writer=obj_writer)
            centroid = root_node.feature_list.get_centroid()
            FromGeometryTreeToTileset.__create_tile(root_node, tileset, centroid, centroid, 0, extension_name, output_dir)
            geometry_tree.root_nodes.remove(root_node)

        if user_arguments.obj is not None:
            obj_writer.write_obj(user_arguments.obj)
        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
        print("\r" + str(FromGeometryTreeToTileset.tile_index), "/", str(FromGeometryTreeToTileset.nb_nodes), "tiles created", flush=True)
        return tileset

    @staticmethod
    def __transform_node(node, user_args, obj_writer=None):
        """
        Apply transformations on the features contained in a node.
        Those transformations are based on the arguments of the user.
        The features can also be writen in an OBJ file.
        :param node: the GeometryNode to transform.
        :param user_args: the Namespace containing the arguments of the command line.
        :param obj_writer: the writer used to create the OBJ model.
        """
        if hasattr(user_args, 'scale') and user_args.scale:
            for objects in node.get_features():
                objects.scale_features(user_args.scale)

        if not all(v == 0 for v in user_args.offset) or user_args.offset[0] == 'centroid':
            if user_args.offset[0] == 'centroid':
                user_args.offset = node.feature_list.get_centroid()
            for objects in node.get_features():
                objects.translate_features(user_args.offset)

        if not user_args.crs_in == user_args.crs_out:
            transformer = Transformer.from_crs(user_args.crs_in, user_args.crs_out)
            for objects in node.get_features():
                objects.change_crs(transformer)

        if user_args.obj is not None:
            for leaf in node.get_leaves():
                obj_writer.add_geometries(leaf.feature_list)

    @staticmethod
    def __create_tile(node, parent, centroid, transform_offset, depth, extension_name=None, output_dir=None):
        print("\r" + str(FromGeometryTreeToTileset.tile_index), "/", str(FromGeometryTreeToTileset.nb_nodes), "tiles created", end='', flush=True)
        objects = node.feature_list
        objects.translate_features(centroid)

        tile = Tile()
        tile.set_geometric_error(node.geometric_error)

        content_b3dm = FromGeometryTreeToTileset.__create_tile_content(objects, extension_name, node.has_texture())
        tile.set_content(content_b3dm)
        tile.set_content_uri(os.path.join('tiles', f'{FromGeometryTreeToTileset.tile_index}.b3dm'))
        tile.write_content(output_dir)
        del tile.attributes["content"].body  # Delete the binary body of the tile once writen on disk to free the memory

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
        node.feature_list.delete_objects_ref()

        FromGeometryTreeToTileset.tile_index += 1
        for child_node in node.child_nodes:
            FromGeometryTreeToTileset.__create_tile(child_node, tile, centroid, [0., 0., 0.], depth + 1, extension_name, output_dir)

    @staticmethod
    def __create_tile_content(objects, extension_name=None, with_texture=False):
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

        gltf = GlTF.from_binary_arrays(arrays, transform, materials=materials)

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

        # Eventually wrap the features together with the optional
        # BatchTableHierarchy within a B3dm:
        return B3dm.from_glTF(gltf, bt=bt)
