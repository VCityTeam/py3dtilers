import numpy as np
from pickle import dumps as pdumps, loads as ploads
import os
import json

from py3dtiles import TileReader
from py3dtiles.feature_table import SemanticPoint
from py3dtiles.points.utils import name_to_filename, node_from_name, SubdivisionType, aabb_size_to_subdivision_type
from py3dtiles.points.points_grid import Grid
from py3dtiles.points.distance import xyz_to_child_index
from py3dtiles.points.task.pnts_writer import points_to_pnts


def node_to_tileset(args):
    return Node.to_tileset(None, args[0], args[1], args[2], args[3], args[4])


class Node(object):
    """docstring for Node"""
    __slots__ = (
        'name', 'aabb', 'aabb_size', 'inv_aabb_size', 'aabb_center',
        'spacing', 'pending_xyz', 'pending_rgb', 'children', 'grid', 'serialized_at',
        'points', 'dirty')

    def __init__(self, name, aabb, spacing):
        super(Node, self).__init__()
        self.name = name
        self.aabb = aabb.astype(np.float32)
        self.aabb_size = (aabb[1] - aabb[0]).astype(np.float32)
        self.inv_aabb_size = (1.0 / self.aabb_size).astype(np.float32)
        self.aabb_center = ((aabb[0] + aabb[1]) * 0.5).astype(np.float32)
        self.spacing = spacing
        self.pending_xyz = []
        self.pending_rgb = []
        self.children = None
        self.grid = Grid(self)
        self.serialized_at = None
        self.points = []
        self.dirty = False

    def save_to_bytes(self):
        sub_pickle = {}
        if self.children is not None:
            sub_pickle['children'] = self.children
            sub_pickle['grid'] = self.grid
        else:
            sub_pickle['points'] = self.points

        d = pdumps(sub_pickle)
        return d

    def load_from_bytes(self, byt):
        sub_pickle = ploads(byt)
        if 'children' in sub_pickle:
            self.children = sub_pickle['children']
            self.grid = sub_pickle['grid']
        else:
            self.points = sub_pickle['points']

    def insert(self, node_catalog, scale, xyz, rgb, make_empty_node=False):
        if make_empty_node:
            self.children = []
            self.pending_xyz += [xyz]
            self.pending_rgb += [rgb]
            return

        # fastpath
        if self.children is None:
            self.points.append((xyz, rgb))
            count = sum([xyz.shape[0] for xyz, rgb in self.points])
            # stop subdividing if spacing is 1mm
            if count >= 20000 and self.spacing > 0.001 * scale:
                self._split(node_catalog, scale)
            self.dirty = True

            return True

        # grid based insertion
        reminder_xyz, reminder_rgb, needs_balance = self.grid.insert(
            self.aabb[0], self.inv_aabb_size, xyz, rgb)

        if needs_balance:
            self.grid.balance(self.aabb_size, self.aabb[0], self.inv_aabb_size)
            self.dirty = True

        self.dirty = self.dirty or (len(reminder_xyz) != len(xyz))

        if len(reminder_xyz) > 0:
            self.pending_xyz += [reminder_xyz]
            self.pending_rgb += [reminder_rgb]

    def needs_balance(self):
        if self.children is not None:
            return self.grid.needs_balance()
        return False


    def flush_pending_points(self, catalog, scale):
        for name, xyz, rgb in self._get_pending_points():
            catalog.get_node(name).insert(catalog, scale, xyz, rgb)
        self.pending_xyz = []
        self.pending_rgb = []

    def dump_pending_points(self):
        result = [
            (name, pdumps({'xyz': xyz, 'rgb': rgb}), len(xyz))
            for name, xyz, rgb in self._get_pending_points()
        ]

        self.pending_xyz = []
        self.pending_rgb = []
        return result

    def get_pending_points_count(self):
        return sum([xyz.shape[0] for xyz in self.pending_xyz])

    def _get_pending_points(self):
        if not self.pending_xyz:
            return

        pending_xyz_arr = np.concatenate(self.pending_xyz)
        pending_rgb_arr = np.concatenate(self.pending_rgb)
        t = aabb_size_to_subdivision_type(self.aabb_size)
        if t == SubdivisionType.QUADTREE:
            indices = xyz_to_child_index(
                pending_xyz_arr,
                np.array(
                    [self.aabb_center[0], self.aabb_center[1], self.aabb[1][2]],
                    dtype=np.float32)
            )
        else:
            indices = xyz_to_child_index(pending_xyz_arr, self.aabb_center)

        # unique children list
        childs = np.unique(indices)

        # make sure all children nodes exist
        for child in childs:
            name = '{}{}'.format(self.name.decode('ascii'), child).encode('ascii')
            # create missing nodes, only for remembering they exist.
            # We don't want to serialize them
            # probably not needed...
            if name not in self.children:
                self.children += [name]
                self.dirty = True
                # print('Added node {}'.format(name))

            mask = np.where(indices - child == 0)
            xyz = pending_xyz_arr[mask]
            if len(xyz) > 0:
                yield name, xyz, pending_rgb_arr[mask]

    def _split(self, node_catalog, scale):
        self.children = []
        for xyz, rgb in self.points:
            self.insert(node_catalog, scale, xyz, rgb)
        self.points = None

    def get_point_count(self, node_catalog, max_depth, depth=0):
        if self.children is None:
            return sum([xyz.shape[0] for xyz, rgb in self.points])
        else:
            count = self.grid.get_point_count()
            if depth < max_depth:
                for n in self.children:
                    count += node_catalog.get_node(n).get_point_count(
                        node_catalog, max_depth, depth + 1)
            return count

    @staticmethod
    def get_points(data, include_rgb):
        if data.children is None:
            points = data.points
            xyz = np.concatenate(tuple([xyz for xyz, rgb in points])).view(np.uint8).ravel()
            rgb = np.concatenate(tuple([rgb for xyz, rgb in points])).ravel()
            count = sum([xyz.shape[0] for xyz, rgb in points])

            if include_rgb:
                result = np.concatenate((xyz, rgb))
                assert len(result) == count * (3 * 4 + 3)
                return result
            else:
                return xyz
        else:
            return data.grid.get_points(include_rgb)

    @staticmethod
    def to_tileset(executor, name, parent_aabb, parent_spacing, folder, scale):
        node = node_from_name(name, parent_aabb, parent_spacing)
        aabb = node.aabb
        ondisk_tile = name_to_filename(folder, name, '.pnts')
        xyz, rgb = None, None

        # Read tile's pnts file, if existing, we'll need it for:
        #   - computing the real AABB (instead of the one based on the octree)
        #   - merging this tile's small (<100 points) children
        if os.path.exists(ondisk_tile):
            tile = TileReader().read_file(ondisk_tile)
            fth = tile.body.feature_table.header
            xyz = tile.body.feature_table.body.positions_arr
            if fth.colors != SemanticPoint.NONE:
                rgb = tile.body.feature_table.body.colors_arr
            xyz_float = xyz.view(np.float32).reshape((fth.points_length, 3))
            # update aabb based on real values
            aabb = np.array([
                np.amin(xyz_float, axis=0),
                np.amax(xyz_float, axis=0)])

        # geometricError is in meters, so we divide it by the scale
        tileset = {'geometricError': 10 * node.spacing / scale[0]}

        children = []
        tile_needs_rewrite = False
        if os.path.exists(ondisk_tile):
            tileset['content'] = {'uri': os.path.relpath(ondisk_tile, folder)}
        for child in ['0', '1', '2', '3', '4', '5', '6', '7']:
            child_name = '{}{}'.format(
                name.decode('ascii'),
                child).encode('ascii')
            child_ondisk_tile = name_to_filename(folder, child_name, '.pnts')

            if os.path.exists(child_ondisk_tile):
                # See if we should merge this child in tile
                if xyz is not None:
                    # Read pnts content
                    tile = TileReader().read_file(child_ondisk_tile)
                    fth = tile.body.feature_table.header

                    # If this child is small enough, merge in the current tile
                    if fth.points_length < 100:
                        xyz = np.concatenate(
                            (xyz,
                             tile.body.feature_table.body.positions_arr))

                        if fth.colors != SemanticPoint.NONE:
                            rgb = np.concatenate(
                                (rgb,
                                 tile.body.feature_table.body.colors_arr))

                        # update aabb
                        xyz_float = tile.body.feature_table.body.positions_arr.view(
                            np.float32).reshape((fth.points_length, 3))

                        aabb[0] = np.amin(
                            [aabb[0], np.min(xyz_float, axis=0)], axis=0)
                        aabb[1] = np.amax(
                            [aabb[1], np.max(xyz_float, axis=0)], axis=0)

                        tile_needs_rewrite = True
                        os.remove(child_ondisk_tile)
                        continue

                # Add child to the to-be-processed list if it hasn't been merged
                if executor is not None:
                    children += [(child_name, node.aabb, node.spacing, folder, scale)]
                else:
                    children += [Node.to_tileset(None, child_name, node.aabb, node.spacing, folder, scale)]

        # If we merged at least one child tile in the current tile
        # the pnts file needs to be rewritten.
        if tile_needs_rewrite:
            os.remove(ondisk_tile)
            count, filename = points_to_pnts(name, np.concatenate((xyz, rgb)), folder, rgb is not None)

        center = ((aabb[0] + aabb[1]) * 0.5).tolist()
        half_size = ((aabb[1] - aabb[0]) * 0.5).tolist()
        tileset['boundingVolume'] = {
            'box': [
                center[0], center[1], center[2],
                half_size[0], 0, 0,
                0, half_size[1], 0,
                0, 0, half_size[2]]
        }

        if executor is not None:
            children = [t for t in executor.map(node_to_tileset, children)]

        if children:
            tileset['children'] = children
        else:
            tileset['geometricError'] = 0.0

        if len(name) > 0 and children:
            if len(json.dumps(tileset)) > 100000:
                tile_root = {
                    'asset': {
                        'version': '1.0',
                    },
                    'refine': 'ADD',
                    'geometricError': tileset['geometricError'],
                    'root': tileset
                }
                tileset_name = 'tileset.{}.json'.format(name.decode('ascii'))
                with open('{}/{}'.format(folder, tileset_name), 'w') as f:
                    f.write(json.dumps(tile_root))
                tileset['content'] = {'uri': tileset_name}
                tileset['children'] = []

        return tileset
