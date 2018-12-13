# -*- coding: utf-8 -*-

import unittest
import numpy as np
# np.set_printoptions(formatter={'int':hex})

from py3dtiles import TileReader, TileContent, Feature, Pnts


class TestTileReader(unittest.TestCase):

    def test_read(self):
        tile = TileReader().read_file('tests/pointCloudRGB.pnts')

        self.assertEqual(tile.header.version, 1.0)
        self.assertEqual(tile.header.tile_byte_length, 15176)
        self.assertEqual(tile.header.ft_json_byte_length, 148)
        self.assertEqual(tile.header.ft_bin_byte_length, 15000)
        self.assertEqual(tile.header.bt_json_byte_length, 0)
        self.assertEqual(tile.header.bt_bin_byte_length, 0)

        feature_table = tile.body.feature_table
        feature = feature_table.feature(0)
        dcol_res = {'Red': 44, 'Blue': 209, 'Green': 243}
        self.assertDictEqual(dcol_res, feature.colors)


class TestTileBuilder(unittest.TestCase):

    def test_build_without_colors(self):
        tread = TileReader().read_file('tests/pointCloudRGB.pnts')
        f0_ref = tread.body.feature_table.feature(0).positions

        # numpy dtype for positions and colors
        pdt = np.dtype([('X', '<f4'), ('Y', '<f4'), ('Z', '<f4')])

        # create features
        features = []
        for i in range(0, tread.body.feature_table.header.points_length):
            f = tread.body.feature_table.feature(i)
            p = f.positions
            pos = np.array([(p['X'], p['Y'], p['Z'])], dtype=pdt).view('uint8')
            newf = Feature.from_array(pdt, pos)
            features.append(newf)

        # create a TileContent
        t = Pnts.from_features(pdt, None, features)

        # configure the TileContent
        rtc = [1215012.8828876738, -4736313.051199594, 4081605.22126042]
        t.body.feature_table.header.rtc = rtc

        # get an array
        tile_arr = t.to_array()
        t2 = Pnts.from_array(tile_arr)
        self.assertEqual(t2.header.version, 1.0)
        self.assertEqual(t2.header.tile_byte_length, 12152)
        self.assertEqual(t2.header.ft_json_byte_length, 124)
        self.assertEqual(t2.header.ft_bin_byte_length, 12000)
        self.assertEqual(t2.header.bt_json_byte_length, 0)
        self.assertEqual(t2.header.bt_bin_byte_length, 0)

        feature_table = t.body.feature_table
        f0 = feature_table.feature(0).positions

        self.assertAlmostEqual(f0_ref['X'], f0['X'])
        self.assertAlmostEqual(f0_ref['Y'], f0['Y'])
        self.assertAlmostEqual(f0_ref['Z'], f0['Z'])

    def test_build(self):
        tread = TileReader().read_file('tests/pointCloudRGB.pnts')

        # numpy dtype for positions and colors
        pdt = np.dtype([('X', '<f4'), ('Y', '<f4'), ('Z', '<f4')])
        cdt = np.dtype([('Red', 'u1'), ('Green', 'u1'), ('Blue', 'u1')])

        # create features
        features = []
        for i in range(0, tread.body.feature_table.header.points_length):
            f = tread.body.feature_table.feature(i)
            p = f.positions
            c = f.colors
            pos = np.array([(p['X'], p['Y'], p['Z'])], dtype=pdt).view('uint8')
            col = np.array([(c['Red'], c['Green'], c['Blue'])],
                           dtype=cdt).view('uint8')
            newf = Feature.from_array(pdt, pos, cdt, col)
            features.append(newf)

        # create a TileContent
        t = Pnts.from_features(pdt, cdt, features)

        # configure the TileContent
        rtc = [1215012.8828876738, -4736313.051199594, 4081605.22126042]
        t.body.feature_table.header.rtc = rtc

        # get an array
        tile_arr = t.to_array()
        t2 = Pnts.from_array(tile_arr)
        self.assertEqual(t2.header.version, 1.0)
        self.assertEqual(t2.header.tile_byte_length, 15176)
        self.assertEqual(t2.header.ft_json_byte_length, 148)
        self.assertEqual(t2.header.ft_bin_byte_length, 15000)
        self.assertEqual(t2.header.bt_json_byte_length, 0)
        self.assertEqual(t2.header.bt_bin_byte_length, 0)

        feature_table = t.body.feature_table
        feature = feature_table.feature(0)
        dcol_res = {'Red': 44, 'Blue': 209, 'Green': 243}
        self.assertDictEqual(dcol_res, feature.colors)

        # t2.save_as("/tmp/py3dtiles_test_build_1.pnts")
