import numpy as np
from pyproj import Transformer
from sortedcollections import OrderedSet
from py3dtiles import B3dm, BatchTable, BoundingVolumeBox, GlTF, GlTFMaterial
from py3dtiles import Tile, TileSet
from ..Texture import Atlas
from ..Common import ObjWriter
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from ..Common import GeometryNode, GeometryTree, FeatureList


class FromGeometryTreeToTileset():
    """
    A static class to create a 3DTiles tileset from a GeometryTree.
    """

    tile_index = 0
    nb_nodes = 0

    @staticmethod
    def convert_to_tileset(geometry_tree: 'GeometryTree', user_arguments=None, extension_name=None, output_dir=None, with_normals=True):
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
        FromGeometryTreeToTileset.tile_index = 0
        FromGeometryTreeToTileset.nb_nodes = geometry_tree.get_number_of_nodes()
        obj_writer = ObjWriter()
        tree_centroid = geometry_tree.get_centroid()
        while len(geometry_tree.root_nodes) > 0:
            root_node = geometry_tree.root_nodes[0]
            root_node.set_node_features_geometry(user_arguments)
            offset = FromGeometryTreeToTileset.__transform_node(root_node, user_arguments, tree_centroid, obj_writer=obj_writer)
            tileset.add_tile(FromGeometryTreeToTileset.__create_tile(root_node, offset, extension_name, output_dir, with_normals))
            geometry_tree.root_nodes.remove(root_node)

        if user_arguments.obj is not None:
            obj_writer.write_obj(user_arguments.obj)
        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
        print("\r" + str(FromGeometryTreeToTileset.tile_index), "/", str(FromGeometryTreeToTileset.nb_nodes), "tiles created", flush=True)
        return tileset

    @staticmethod
    def __transform_node(node: 'GeometryNode', user_args, tree_centroid=np.array([0, 0, 0]), obj_writer=None):
        """
        Apply transformations on the features contained in a node.
        Those transformations are based on the arguments of the user.
        The features can also be writen in an OBJ file.
        :param node: the GeometryNode to transform.
        :param user_args: the Namespace containing the arguments of the command line.
        :param obj_writer: the writer used to create the OBJ model.
        """
        if hasattr(user_args, 'height_mult') and user_args.height_mult:
            for feature_list in node.get_features():
                feature_list.height_mult_features(user_args.height_mult)
            tree_centroid = np.array([tree_centroid[0], tree_centroid[1], tree_centroid[2] * user_args.height_mult])

        if hasattr(user_args, 'scale') and user_args.scale:
            for feature_list in node.get_features():
                feature_list.scale_features(user_args.scale, tree_centroid)

        offset = np.array([0, 0, 0]) if user_args.offset[0] == 'centroid' else np.array(user_args.offset)
        transform_offset = node.feature_list.get_centroid() + offset

        if not user_args.crs_in == user_args.crs_out:
            transformer = Transformer.from_crs(user_args.crs_in, user_args.crs_out)
            tree_centroid = np.array(transformer.transform((tree_centroid + offset)[0], (tree_centroid + offset)[1], (tree_centroid + offset)[2]))
            for feature_list in node.get_features():
                feature_list.change_crs(transformer, offset)
            transform_offset = node.feature_list.get_centroid()

        distance = node.feature_list.get_centroid() - tree_centroid

        for feature_list in node.get_features():
            feature_list.translate_features(-feature_list.get_centroid())

        if user_args.obj is not None:
            for leaf in node.get_leaves():
                # Since the tiles are centered on [0, 0, 0], we use an offset to place the geometries in the OBJ model
                obj_writer.add_geometries(leaf.feature_list, offset=distance)
        return distance if user_args.offset[0] == 'centroid' else transform_offset

    @staticmethod
    def __create_tile(node: 'GeometryNode', transform_offset, extension_name=None, output_dir=None, with_normals=True):
        """
        Create a tile from a node. Recursively create tiles from the children of the node.
        :param node: the GeometryNode.
        :param transform_offset: the X,Y,Z position of the tile, relative to its parent's position.
        :param extension_name: the name of the extension to create.
        :param output_dir: the directory where the tiles will be created.
        """
        print("\r" + str(FromGeometryTreeToTileset.tile_index), "/", str(FromGeometryTreeToTileset.nb_nodes), "tiles created", end='', flush=True)
        feature_list = node.feature_list

        tile = Tile()
        tile.set_geometric_error(node.geometric_error)

        content_b3dm = FromGeometryTreeToTileset.__create_tile_content(feature_list, extension_name, node.has_texture(), node.downsample_factor, with_normals)
        tile.set_content(content_b3dm)
        tile.set_content_uri('tiles/' + f'{FromGeometryTreeToTileset.tile_index}.b3dm')
        tile.write_content(output_dir)
        del tile.attributes["content"].body  # Delete the binary body of the tile once writen on disk to free the memory

        # Set the position of the tile. The position is relative to the parent tile's position
        tile.set_transform([1, 0, 0, 0,
                            0, 1, 0, 0,
                            0, 0, 1, 0,
                            transform_offset[0], transform_offset[1], transform_offset[2], 1])
        tile.set_refine_mode('REPLACE')
        bounding_box = BoundingVolumeBox()
        for feature in feature_list:
            bounding_box.add(feature.get_bounding_volume_box())

        if extension_name is not None:
            extension = feature_list.__class__.create_bounding_volume_extension(extension_name, None, feature_list)
            if extension is not None:
                bounding_box.add_extension(extension)

        tile.set_bounding_volume(bounding_box)

        del node.feature_list

        FromGeometryTreeToTileset.tile_index += 1
        for child_node in node.child_nodes:
            tile.add_child(FromGeometryTreeToTileset.__create_tile(child_node, [0., 0., 0.], extension_name, output_dir, with_normals))

        return tile

    @staticmethod
    def __create_tile_content(feature_list: 'FeatureList', extension_name=None, with_texture=False, downsample_factor=1, with_normals=True):
        """
        :param pre_tile: an array containing features of a single tile

        :return: a B3dm tile.
        """
        # create B3DM content
        arrays = []
        materials = []
        seen_mat_indexes = dict()
        if with_texture:
            tile_atlas = Atlas(feature_list, downsample_factor)
            materials = [GlTFMaterial(textureUri='./' + tile_atlas.id)]
        for feature in feature_list:
            mat_index = feature.material_index
            if mat_index not in seen_mat_indexes and not with_texture:
                seen_mat_indexes[mat_index] = len(materials)
                materials.append(feature_list.get_material(mat_index))
            content = {
                'position': feature.geom.getPositionArray(),
                'normal': feature.geom.getNormalArray(),
                'bbox': [[float(i) for i in j] for j in feature.geom.getBbox()],
                'matIndex': seen_mat_indexes[mat_index] if not with_texture else 0
            }
            if with_texture:
                content['uv'] = feature.geom.getDataArray(0)
            if feature.has_vertex_colors:
                content['vertex_color'] = feature.geom.getDataArray(int(with_texture))
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

        gltf = GlTF.from_binary_arrays(arrays, transform, materials=materials, withNormals=with_normals)

        # Create a batch table and add the ID of each feature to it
        ids = [feature.get_id() for feature in feature_list]
        bt = BatchTable()
        bt.add_property_from_array("id", ids)

        # if there is application specific data associated with the features, add it to the batch table
        features_data = [feature.get_batchtable_data() for feature in feature_list]
        if all([feature_data for feature_data in features_data]):
            # Construct a set of all possible batch table keys
            bt_keys = OrderedSet()
            for key_subset in [feature_data.keys() for feature_data in features_data]:
                for key in key_subset:
                    bt_keys.add(key)

            # add feature data to batch table based on possible keys
            for key in bt_keys:
                key_data = [feature_data.get(key, None) for feature_data in features_data]
                bt.add_property_from_array(key, key_data)

        if extension_name is not None:
            extension = feature_list.__class__.create_batch_table_extension(extension_name, ids, feature_list)
            if extension is not None:
                bt.add_extension(extension)

        # Eventually wrap the features together with the optional
        # BatchTableHierarchy within a B3dm:
        return B3dm.from_glTF(gltf, bt=bt)
