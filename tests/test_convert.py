# -*- coding: utf-8 -*-

import unittest

from py3dtiles import convert_to_ecef


class TestConvert(unittest.TestCase):

    def test_convert(self):

        # results tested with gdaltransform
        [x, y, z] = convert_to_ecef(-75.61200462622627,
                                    40.03886513981721,
                                    2848.448771114095,
                                    4326)
        self.assertAlmostEqual(x, 1215626.30684538)
        self.assertAlmostEqual(y, -4738673.45914053)
        self.assertAlmostEqual(z, 4083122.83975827)
