# -*- coding: utf-8 -*-

import unittest
import numpy as np
import binascii
import json
# np.set_printoptions(formatter={'int':hex})

from py3dtiles import TileReader, B3dm, GlTF, TriangleSoup

class TestTileReader(unittest.TestCase):

    def test_read(self):
        tile = TileReader().read_file('tests/dragon_low.b3dm')

        self.assertEqual(tile.header.version, 1.0)
        self.assertEqual(tile.header.tile_byte_length, 47246)
        self.assertEqual(tile.header.ft_json_byte_length, 20)
        self.assertEqual(tile.header.ft_bin_byte_length, 0)
        self.assertEqual(tile.header.bt_json_byte_length, 0)
        self.assertEqual(tile.header.bt_bin_byte_length, 0)

        with open('tests/dragon_low_gltf_header.json', 'r') as f:
            gltf_header = json.loads(f.read())
        self.assertDictEqual(gltf_header, tile.body.glTF.header)


class TestTileBuilder(unittest.TestCase):

    def test_build(self):
        with open('tests/building.wkb', 'rb') as f:
            wkb = f.read()
        ts = TriangleSoup.from_wkb_multipolygon(wkb)
        positions = ts.getPositionArray()
        normals = ts.getNormalArray()
        box = [[-8.74748499994166, -7.35523200035095, -2.05385796777344],
               [8.8036420000717, 7.29930999968201, 2.05386103222656]]
        arrays = [{
            'position': positions,
            'normal': normals,
            'bbox': box
        }]

        transform = np.array([
            [1, 0, 0, 1842015.125],
            [0, 1, 0, 5177109.25],
            [0, 0, 1, 247.87364196777344],
            [0, 0, 0, 1]], dtype=float)
        # translation : 1842015.125, 5177109.25, 247.87364196777344
        transform = transform.flatten('F')
        glTF = GlTF.from_binary_arrays(arrays, transform)
        t = B3dm.from_glTF(glTF)

        # get an array
        tile_arr = t.to_array()
        self.assertEqual(t.header.version, 1.0)
        self.assertEqual(t.header.tile_byte_length, 2952)
        self.assertEqual(t.header.ft_json_byte_length, 0)
        self.assertEqual(t.header.ft_bin_byte_length, 0)
        self.assertEqual(t.header.bt_json_byte_length, 0)
        self.assertEqual(t.header.bt_bin_byte_length, 0)

        # t.save_as("/tmp/py3dtiles_test_build_1.b3dm")

class TestTexturedTileBuilder(unittest.TestCase):

    def test_build(self):
        with open('tests/square.wkb', 'rb') as f:
            wkb = f.read()
        with open('tests/squareUV.wkb', 'rb') as f:
            wkbuv = f.read()
        ts = TriangleSoup.from_wkb_multipolygon(wkb, [wkbuv])
        positions = ts.getPositionArray()
        normals = ts.getNormalArray()
        uvs = ts.getDataArray(0)
        box = [[0, 0, 0],
               [10, 10, 0]]
        arrays = [{
            'position': positions,
            'normal': normals,
            'uv': uvs,
            'bbox': box
        }]

        transform = np.array([
            [1, 0, 0, 0],
            [0, 1, 0, 0],
            [0, 0, 1, 0],
            [0, 0, 0, 1]], dtype=float)
        transform = transform.flatten('F')
        glTF = GlTF.from_binary_arrays(arrays, transform, textureUri='squaretexture.jpg')
        t = B3dm.from_glTF(glTF)

        # get an array
        tile_arr = t.to_array()
        self.assertEqual(t.header.version, 1.0)
        self.assertEqual(t.header.tile_byte_length, 1556)
        self.assertEqual(t.header.ft_json_byte_length, 0)
        self.assertEqual(t.header.ft_bin_byte_length, 0)
        self.assertEqual(t.header.bt_json_byte_length, 0)
        self.assertEqual(t.header.bt_bin_byte_length, 0)

        # t.save_as("/tmp/py3dtiles_test_build_1.b3dm")
