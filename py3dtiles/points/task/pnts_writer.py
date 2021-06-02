import numpy as np
import pickle
import struct
import os
import py3dtiles
import lz4.frame as gzip
from py3dtiles.points.utils import name_to_filename


class _DummyNode():
    def __init__(self, _bytes):
        if 'children' in _bytes:
            self.children = _bytes['children']
            self.grid = _bytes['grid']
        else:
            self.children = None
            self.points = _bytes['points']


def points_to_pnts(name, points, out_folder, include_rgb):
    count = int(len(points) / (3 * 4 + (3 if include_rgb else 0)))

    if count == 0:
        return 0, None

    pdt = np.dtype([('X', '<f4'), ('Y', '<f4'), ('Z', '<f4')])
    cdt = np.dtype([('Red', 'u1'), ('Green', 'u1'), ('Blue', 'u1')]) if include_rgb else None

    ft = py3dtiles.feature_table.FeatureTable()
    ft.header = py3dtiles.feature_table.FeatureTableHeader.from_dtype(pdt, cdt, count)
    ft.body = py3dtiles.feature_table.FeatureTableBody.from_array(ft.header, points)

    body = py3dtiles.pnts.PntsBody()
    body.feature_table = ft

    tile = py3dtiles.tile.Tile()
    tile.body = body
    tile.header = py3dtiles.pnts.PntsHeader()
    tile.header.sync(body)

    filename = name_to_filename(out_folder, name, '.pnts')

    assert not os.path.exists(filename), '{} already written'.format(filename)

    tile.save_as(filename)

    return count, filename


def node_to_pnts(name, node, out_folder, include_rgb):
    from py3dtiles.points.node import Node
    points = Node.get_points(node, include_rgb)
    return points_to_pnts(name, points, out_folder, include_rgb)


def run(sender, data, node_name, folder, write_rgb):
    # we can safely write the .pnts file
    if len(data):
        root = pickle.loads(gzip.decompress(data))
        # print('write ', node_name.decode('ascii'))
        total = 0
        for name in root:
            node = _DummyNode(pickle.loads(root[name]))
            total += node_to_pnts(name, node, folder, write_rgb)[0]

        sender.send_multipart([b'pnts', struct.pack('>I', total), node_name])
