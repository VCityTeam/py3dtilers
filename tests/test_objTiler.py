import unittest
import os
from argparse import Namespace

from py3dtilers.ObjTiler.ObjTiler import ObjTiler


class Test_Tile(unittest.TestCase):

    def test_basic_case(self):
        path = 'tests/obj_tiler_data/Cube'
        obj_tiler = ObjTiler()
        obj_tiler.current_path = "basic_case"
        directory = "tests/obj_tiler_data/generated_tilesets/"
        obj_tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory)
        if not os.path.exists('tests/obj_tiler_data/generated_tilesets'):
            os.makedirs('tests/obj_tiler_data/generated_tilesets')

        tileset = obj_tiler.from_obj_directory(path)
        if(tileset is not None):
            tileset.write_to_directory("tests/obj_tiler_data/generated_tilesets/" + obj_tiler.current_path)

    def test_texture(self):
        path = 'tests/obj_tiler_data/TexturedCube'
        obj_tiler = ObjTiler()
        obj_tiler.current_path = "texture"
        directory = "tests/obj_tiler_data/generated_tilesets/"
        offset = [-1843397, -5173891, -300]
        obj_tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=offset, with_texture=True, scale=50, output_dir=directory)
        if not os.path.exists('tests/obj_tiler_data/generated_tilesets'):
            os.makedirs('tests/obj_tiler_data/generated_tilesets')

        tileset = obj_tiler.from_obj_directory(path)
        if(tileset is not None):
            tileset.write_to_directory("tests/obj_tiler_data/generated_tilesets/" + obj_tiler.current_path)


if __name__ == '__main__':
    unittest.main()
