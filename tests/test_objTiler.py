import unittest
import os
from py3dtiles import BoundingVolumeBox

from py3dtilers.ObjTiler.ObjTiler import from_obj_directory


class Test_Tile(unittest.TestCase):

    def test_basic_case(self):
        path = 'tests/obj_tiler_data'

        if not os.path.exists('tests/obj_tiler_data/generated_tilesets'):
            os.makedirs('tests/obj_tiler_data/generated_tilesets')

        tileset = from_obj_directory(path)
        if(tileset is not None):
            tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
            folder_name = "basic_case"
            print("tileset in tests/obj_tiler_data/generated_tilesets/" + folder_name)
            tileset.write_to_directory("tests/obj_tiler_data/generated_tilesets/" + folder_name)


if __name__ == '__main__':
    unittest.main()
