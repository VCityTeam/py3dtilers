from pathlib import Path
import numpy as np
from pyproj import Transformer
from sortedcollections import OrderedSet
from pygltflib import VEC3, FLOAT
from py3dtiles.tileset.content import B3dm, GltfAttribute, GltfPrimitive
from py3dtiles.tileset.content.batch_table import BatchTable
from py3dtiles.tileset.content.b3dm_feature_table import B3dmFeatureTable
from py3dtiles.tileset import Tile, TileSet, BoundingVolumeBox
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
        root_tile = Tile(geometric_error=500, bounding_volume=BoundingVolumeBox())
        FromGeometryTreeToTileset.tile_index = 0
        FromGeometryTreeToTileset.nb_nodes = geometry_tree.get_number_of_nodes()
        obj_writer = ObjWriter()
        tree_centroid = geometry_tree.get_centroid()
        while len(geometry_tree.root_nodes) > 0:
            root_node = geometry_tree.root_nodes[0]
            root_node.set_node_features_geometry(user_arguments)
            offset = FromGeometryTreeToTileset.__transform_node(root_node, user_arguments, tree_centroid, obj_writer=obj_writer)
            root_tile.add_child(FromGeometryTreeToTileset.__create_tile(root_node, offset, extension_name, output_dir, with_normals))
            geometry_tree.root_nodes.remove(root_node)

        if user_arguments.obj is not None:
            obj_writer.write_obj(user_arguments.obj)
        tileset.root_tile = root_tile
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

        tile = Tile(geometric_error=node.geometric_error,
                    content_uri=Path('tiles', f'{FromGeometryTreeToTileset.tile_index}.b3dm'),
                    transform=np.array([[1, 0, 0, transform_offset[0]],
                                        [0, 1, 0, transform_offset[1]],
                                        [0, 0, 1, transform_offset[2]],
                                        [0, 0, 0, 1]]),
                    refine_mode='REPLACE')

        content_b3dm = FromGeometryTreeToTileset.__create_tile_content(feature_list, extension_name, node.has_texture(), node.downsample_factor, with_normals)
        tile.tile_content = content_b3dm
        tile.write_content(output_dir)
        # del tile.attributes["content"].body  # Delete the binary body of the tile once writen on disk to free the memory

        bounding_box = BoundingVolumeBox()
        for feature in feature_list:
            bounding_box.add(feature.get_bounding_volume_box())

        if extension_name is not None:
            extension = feature_list.__class__.create_bounding_volume_extension(extension_name, None, feature_list)
            if extension is not None:
                bounding_box.extensions[extension.name] = extension

        tile.bounding_volume = bounding_box

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
                              0, 0, 0, 1], dtype=np.float32)

        primitives = FromGeometryTreeToTileset.__group_by_material_index(feature_list, with_texture, downsample_factor, with_normals)

        # Create a batch table and add the ID of each feature to it
        ids = [feature.get_id() for feature in feature_list]
        ft = B3dmFeatureTable()
        ft.header.data['BATCH_LENGTH'] = len(ids)
        bt = BatchTable()
        bt.add_property_as_json("id", ids)

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
                bt.add_property_as_json(key, key_data)

        if extension_name is not None:
            extension = feature_list.__class__.create_batch_table_extension(extension_name, ids, feature_list)
            if extension is not None:
                if 'extensions' not in bt.header.data:
                    bt.header.data['extensions'] = {}
                bt.header.data['extensions'][extension.name] = extension.to_dict()

        # Eventually wrap the features together with the optional
        # BatchTableHierarchy within a B3dm:
        return B3dm.from_primitives(primitives, batch_table=bt, feature_table=ft, transform=transform)

    @staticmethod
    def __group_by_material_index(feature_list: 'FeatureList', with_texture: int, downsample_factor=1, with_normals=True):
        primitives = {}
        seen_mat_indexes = []
        batch_id = 0

        texture_uri = Atlas(feature_list, downsample_factor).id if with_texture else None
        for feature in feature_list:
            mat_index = feature.material_index

            if mat_index not in seen_mat_indexes:
                seen_mat_indexes.append(mat_index)
                additional_attributes_dict = {}
                if feature.has_vertex_colors:
                    additional_attributes_dict['COLOR_0'] = []
                primitives[mat_index] = {'positions': [], 'normals': [], 'uvs': [], 'batchids': [], 'texture_uri': texture_uri, 'material': feature_list.get_material(mat_index), 'additional_attributes': additional_attributes_dict}

            primitive = primitives[mat_index]

            positions = np.array(feature.get_geom_as_triangles(), dtype=np.float32).flatten().reshape((-1, 3))
            primitive['positions'].append(positions)
            if with_normals:
                primitive['normals'].append(feature.geom.compute_normals())
            if with_texture:
                primitive['uvs'].append(feature.geom.get_data(0).astype(np.float32))
            primitive['batchids'].append(np.full(len(positions), batch_id, dtype=np.uint32))
            if feature.has_vertex_colors:
                primitive['additional_attributes']['COLOR_0'].append(feature.geom.get_data(int(with_texture)))

            batch_id += 1

        gltf_primitives = []
        for primitive in primitives.values():
            additional_attributes = []
            for attribute in primitive['additional_attributes']:
                additional_attributes.append(GltfAttribute(attribute, VEC3, FLOAT, np.concatenate(primitive['additional_attributes'][attribute])))
            points = np.concatenate(primitive['positions'])
            normals = np.concatenate(primitive['normals'], dtype=np.float32) if with_normals else None
            uvs = np.concatenate(primitive['uvs'], dtype=np.float32) if with_texture else None
            batchids = np.concatenate(primitive['batchids'])
            gltf_primitives.append(GltfPrimitive(points, normals=normals, uvs=uvs, batchids=batchids, additional_attributes=additional_attributes, texture_uri=primitive['texture_uri'], material=primitive['material']))

        return gltf_primitives
