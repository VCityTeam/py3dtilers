#! /usr/bin/env python
# -*- coding: utf-8 -*-
from py3dtiles import TileReader


def print_pnts_info(tile):
    # tile header
    th = tile.header
    print("Tile Header")
    print("-----------")
    print("Magic Value: ", th.magic_value)
    print("Version: ", th.version)
    print("Tile byte length: ", th.tile_byte_length)
    print("Feature table json byte length: ", th.ft_json_byte_length)
    print("Feature table bin byte length: ", th.ft_bin_byte_length)

    # feature table header
    fth = tile.body.feature_table.header
    print("")
    print("Feature Table Header")
    print("--------------------")
    print(fth.to_json())

    # first point data
    if fth.points_length > 0:
        print("")
        print("First point")
        print("-----------")
        f = tile.body.feature_table.feature(0)
        d = f.positions
        d.update(f.colors)
        print(d)


def print_b3dm_info(tile):
    # tile header
    th = tile.header
    print("Tile Header")
    print("-----------")
    print("Magic Value: ", th.magic_value)
    print("Version: ", th.version)
    print("Tile byte length: ", th.tile_byte_length)
    print("Feature table json byte length: ", th.ft_json_byte_length)
    print("Feature table bin byte length: ", th.ft_bin_byte_length)
    print("Batch table json byte length: ", th.bt_json_byte_length)
    print("Batch table bin byte length: ", th.bt_bin_byte_length)

    gltfh = tile.body.glTF.header
    print("")
    print("glTF Header")
    print("-----------")
    print(gltfh)


def main(args):
    tile = TileReader().read_file(args.filename)
    magic = tile.header.magic_value

    if magic == "pnts":
        print_pnts_info(tile)
    elif magic == "b3dm":
        print_b3dm_info(tile)
    else:
        raise RuntimeError("Unsupported format " + magic)


def init_parser(subparser, str2bool):
    # arg parse
    parser = subparser.add_parser('info', help='Extract informations from a 3DTiles file')

    parser.add_argument('filename', type=str)
