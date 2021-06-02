#! /usr/bin/env python
# -*- coding: utf-8 -*-

import argparse
import psycopg2
import getpass
import math
import json
import os
import errno
import numpy as np
from py3dtiles import TriangleSoup, GlTF, B3dm, BatchTable, TileSet


class BoundingBox():
    def __init__(self, minimum, maximum):
        self.min = [float(i) for i in minimum]
        self.max = [float(i) for i in maximum]

    def inside(self, point):
        return ((self.min[0] <= point[0] < self.max[0])
            and (self.min[1] <= point[1] < self.max[1]))

    def center(self):
        return [(i + j) / 2 for (i,j) in zip(self.min, self.max)]

    def add(self, box):
        self.min = [min(i,j) for (i,j) in zip(self.min, box.min)]
        self.max = [max(i,j) for (i,j) in zip(self.max, box.max)]


class Feature():
    def __init__(self, index, box):
        self.index = index
        self.box = box


class Node():
    counter = 0

    def __init__(self, features=[]):
        self.id = Node.counter
        Node.counter += 1
        self.features = features
        self.box = None
        self.children = []

    def add(self, node):
        self.children.append(node)

    def compute_bbox(self):
        self.box = BoundingBox(
            [float("inf"), float("inf"), float("inf")],
            [-float("inf"), -float("inf"), -float("inf")])
        for c in self.children:
            c.compute_bbox()
            self.box.add(c.box)
        for g in self.features:
            self.box.add(g.box)

    def to_tileset(self, transform):
        self.compute_bbox()
        tiles = TileSet()
        error = 500   # TODO, shouldn't be hardwired
        tiles.set_geometric_error(error)
        tiles.header.root.update(self.to_tileset_r(error))
        tiles.set_transform(transform)
        return tiles

    def to_tileset_r(self, error):
        (c1, c2) = (self.box.min, self.box.max)
        center = [(c1[i] + c2[i]) / 2 for i in range(0, 3)]
        xAxis = [(c2[0] - c1[0]) / 2, 0, 0]
        yAxis = [0, (c2[1] - c1[1]) / 2, 0]
        zAxis = [0, 0, (c2[2] - c1[2]) / 2]
        box = [round(x, 3) for x in center + xAxis + yAxis + zAxis]
        tile = {
            "boundingVolume": {
                "box": box
            },
            "geometricError": error,  # TODO
            "children": [n.to_tileset_r(error / 2.) for n in self.children],
            "refine": "add"
        }
        if len(self.features) != 0:
            tile["content"] = {
                "uri": "tiles/{0}.b3dm".format(self.id)
            }

        return tile

    def all_nodes(self):
        nodes = [self]
        for c in self.children:
            nodes.extend(c.all_nodes())
        return nodes


def tile_extent(extent, size, i, j):
    minExtent = [
        extent.min[0] + i * size,
        extent.min[1] + j * size]
    maxExtent = [
        extent.min[0] + (i + 1) * size,
        extent.min[1] + (j + 1) * size]
    return BoundingBox(minExtent, maxExtent)


# TODO: transform
def arrays2tileset(positions, normals, bboxes, transform, ids=None):
    """
    :rtype: None, the tile-set is directly written on disk (in current
            working directory)
    :param ids: optional identifiers (not part of the core tile-set)
                stored in a batch-table
    """
    print("Creating tileset...")
    maxTileSize = 2000
    featuresPerTile = 20
    indices = [i for i in range(len(positions))]

    # glTF is Y-up, so to get the bounding boxes in the 3D tiles
    # coordinate system, we have to apply a Y-to-Z transform to the
    # glTF bounding boxes
    zUpBboxes = []
    for bbox in bboxes:
        tmp = m = bbox[0]
        M = bbox[1]
        m = [m[0], -m[2], m[1]]
        M = [M[0], -tmp[2], M[1]]
        zUpBboxes.append([m, M])

    # Compute extent
    xMin = yMin = float('inf')
    xMax = yMax = - float('inf')

    for bbox in zUpBboxes:
        xMin = min(xMin, bbox[0][0])
        yMin = min(yMin, bbox[0][1])
        xMax = max(xMax, bbox[1][0])
        yMax = max(yMax, bbox[1][1])
    extent = BoundingBox([xMin, yMin], [xMax, yMax])
    extentX = xMax - xMin
    extentY = yMax - yMin

    # Create quadtree
    treeRoot = Node()
    for i in range(0, int(math.ceil(extentX / maxTileSize))):
        for j in range(0, int(math.ceil(extentY / maxTileSize))):
            tile = tile_extent(extent, maxTileSize, i, j)

            geoms = []
            for idx, box in zip(indices, zUpBboxes):
                bbox = BoundingBox(box[0], box[1])

                if tile.inside(bbox.center()):
                    geoms.append(Feature(idx, bbox))

            if len(geoms) == 0:
                continue

            if len(geoms) > featuresPerTile:
                node = Node(geoms[0:featuresPerTile])
                treeRoot.add(node)
                divide(tile, geoms[featuresPerTile:len(geoms)], i * 2,
                       j * 2, maxTileSize / 2., featuresPerTile, node)
            else:
                node = Node(geoms)
                treeRoot.add(node)

    treeRoot.compute_bbox()

    # Export b3dm & tileset
    tileset = treeRoot.to_tileset(transform)
    # FIXME: what is the node.id format argument for ?
    f = open("tileset.json".format(node.id), 'w')
    f.write(tileset.to_json())
    print("Creating tiles...")
    nodes = treeRoot.all_nodes()
    identity = np.identity(4).flatten('F')
    try:
        os.makedirs("tiles")
    except OSError as e:
        if e.errno != errno.EEXIST:
            raise
    for node in nodes:
        if len(node.features) != 0:
            binarrays = []
            gids = []
            for feature in node.features:
                pos = feature.index
                binarrays.append({
                    'position': positions[pos],
                    'normal': normals[pos],
                    'bbox': [[float(i) for i in j] for j in bboxes[pos]],
                })
                if ids is not None:
                    gids.append(ids[pos])
            gltf = GlTF.from_binary_arrays(binarrays, identity)
            bt = None
            if ids is not None:
                bt = BatchTable()
                bt.add_property_from_array("id", gids)
            b3dm = B3dm.from_glTF(gltf, bt).to_array()
            f = open("tiles/{0}.b3dm".format(node.id), 'wb')
            f.write(b3dm)


def divide(extent, geometries, xOffset, yOffset, tileSize,
           featuresPerTile, parent):
    for i in range(0, 2):
        for j in range(0, 2):
            tile = tile_extent(extent, tileSize, i, j)

            geoms = []
            for g in geometries:
                if tile.inside(g.box.center()):
                    geoms.append(g)
            if len(geoms) == 0:
                continue

            if len(geoms) > featuresPerTile:
                node = Node(geoms[0:featuresPerTile])
                parent.add(node)
                divide(tile, geoms[featuresPerTile:len(geoms)],
                       (xOffset + i) * 2, (yOffset + j) * 2,
                       tileSize / 2., featuresPerTile, node)
            else:
                node = Node(geoms)
                parent.add(node)


def wkbs2tileset(wkbs, ids, transform):
    geoms = [TriangleSoup.from_wkb_multipolygon(wkb) for wkb in wkbs]
    positions = [ts.getPositionArray() for ts in geoms]
    normals = [ts.getNormalArray() for ts in geoms]
    bboxes = [ts.getBbox() for ts in geoms]
    arrays2tileset(positions, normals, bboxes, transform, ids)


def from_db(db_name, table_name, column_name, id_column_name, user_name):
    user = getpass.getuser() if user_name is None else user_name

    try:
        connection = psycopg2.connect(dbname=db_name, user=user)
    except psycopg2.OperationalError:
        pw = getpass.getpass("Postgres password for user {}\n".format(user))
        connection = psycopg2.connect(dbname=db_name, user=user, password=pw)

    cur = connection.cursor()

    print("Loading data from database...")
    cur.execute("SELECT ST_3DExtent({0}) FROM {1}".format(column_name, table_name))
    extent = cur.fetchall()[0][0]
    extent = [m.split(" ") for m in extent[6:-1].split(",")]
    offset = [(float(extent[1][0]) + float(extent[0][0])) / 2,
              (float(extent[1][1]) + float(extent[0][1])) / 2,
              (float(extent[1][2]) + float(extent[0][2])) / 2]

    id_statement = ""
    if id_column_name is not None:
        id_statement = "," + id_column_name
    cur.execute("SELECT ST_AsBinary(ST_RotateX(ST_Translate({0}, {1}, {2}, {3}), -pi() / 2)),"
                "ST_Area(ST_Force2D({0})) AS weight{5} FROM {4} ORDER BY weight DESC"
                .format(column_name, -offset[0], -offset[1], -offset[2],
                        table_name, id_statement))
    res = cur.fetchall()
    wkbs = [t[0] for t in res]
    ids = None
    if id_column_name is not None:
        ids = [t[2] for t in res]
    transform = np.array([
        [1, 0, 0, offset[0]],
        [0, 1, 0, offset[1]],
        [0, 0, 1, offset[2]],
        [0, 0, 0, 1]], dtype=float)
    transform = transform.flatten('F')

    wkbs2tileset(wkbs, ids, transform)


def from_directory(directory, offset):
    # TODO: improvement -> order wkbs by geometry size, similarly to database mode
    offset = (0,0,0) if offset is None else offset
    # open all wkbs from directory
    files = os.listdir(directory)
    files = [os.path.join(directory, f) for f in os.listdir(directory)]
    files = [f for f in files if os.path.isfile(f) and os.path.splitext(f)[1] == '.wkb']
    wkbs = []
    for f in files:
        of = open(f, 'rb')
        wkbs.append(of.read())
        of.close()

    transform = np.array([
        [1, 0, 0, offset[0]],
        [0, 1, 0, offset[1]],
        [0, 0, 1, offset[2]],
        [0, 0, 0, 1]], dtype=float)
    transform = transform.flatten('F')
    wkbs2tileset(wkbs, None, transform)


def init_parser(subparser, str2bool):
    descr = 'Generate a tileset from a set of geometries'
    parser = subparser.add_parser('export', help=descr)

    group = parser.add_mutually_exclusive_group()

    d_help = 'name of the directory containing the geometries'
    group.add_argument('-d', metavar='DIRECTORY', type=str, help=d_help)

    o_help = 'offset of the geometries (only with -d)'
    parser.add_argument('-o', nargs=3, metavar=('X', 'Y', 'Z'), type=float, help=o_help)

    D_help = 'database name'
    group.add_argument('-D', metavar='DATABASE', type=str, help=D_help)

    t_help = 'table name'
    parser.add_argument('-t', metavar='TABLE', type=str, help=t_help)

    c_help = 'geometry column name'
    parser.add_argument('-c', metavar='COLUMN', type=str, help=c_help)

    parser.add_argument('-i', metavar='IDCOLUMN', type=str, help=c_help)

    u_help = 'database user name'
    parser.add_argument('-u', metavar='USER', type=str, help=u_help)


def main(args):
    if args.D is not None:
        if args.t is None or args.c is None:
            print('Error: please define a table (-t) and column (-c)')
            exit()

        from_db(args.D, args.t, args.c, args.i, args.u)
    elif args.d is not None:
        from_directory(args.d, args.o)
    else:
        raise NameError('Error: database or directory must be set')
