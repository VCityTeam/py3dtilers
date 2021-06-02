# -*- coding: utf-8 -*-
import json
import unittest
from py3dtiles import BoundingVolumeBox, HelperTest, Tile, TileSet


class Test_TileSet(unittest.TestCase):

    def test_basics(self):
        helper = HelperTest(lambda x: TileSet().validate(x))
        helper.sample_file_names.append('TileSet_CanaryWharf.json')
        if not helper.check():
            self.fail()

    @classmethod
    def build_sample(cls):
        """
        Programmatically define a tileset sample encountered in the
        TileSet json header specification cf
        https://github.com/AnalyticalGraphicsInc/3d-tiles/tree/master/specification#tileset-json
        :return: the sample as TileSet object.
        """
        tile_set = TileSet()
        bounding_volume = BoundingVolumeBox()
        bounding_volume.set_from_list([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
        root_tile = Tile()
        root_tile.set_bounding_volume(bounding_volume)
        root_tile.set_geometric_error(3.14159)
        # Setting the mode to the default mode does not really change things.
        # The following line is thus just here ot test the "callability" of
        # set_refine_mode():
        root_tile.set_refine_mode('ADD')
        tile_set.set_root_tile(root_tile)
        #FIXME bt.add_property_from_array("id",
        #FIXME                           ["unique id", "another unique id"])
        return tile_set

    def test_json_encoding(self):
        return self.build_sample().to_json()

    def test_tileset_build_sample_and_validate(self):
        if not self.build_sample().validate():
            self.fail()

if __name__ == "__main__":
    unittest.main()
