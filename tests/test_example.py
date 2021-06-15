# -*- coding: utf-8 -*-
import unittest
from py3dtilers.Common.kd_tree import kd_tree
from py3dtiles import BoundingVolumeBox


class Test_kd_tree(unittest.TestCase):

    def test_basics(self):
        # a = kd_tree()
        print('Make some test...')
        bbox = BoundingVolumeBox()

if __name__ == "__main__":
    unittest.main()