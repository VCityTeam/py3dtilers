import unittest
import os
from argparse import Namespace
from py3dtiles import TilesetReader

from py3dtilers.TilesetReader.TilesetReader import B3dmTiler


class Test_Tile(unittest.TestCase):

    def test_basic_case(self):
        tiler = B3dmTiler()
        tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False)
        path = "tests/tileset_reader_test_data/white_buildings/"
        if not os.path.exists('tests/tileset_reader_test_data/generated_tilesets'):
            os.makedirs('tests/tileset_reader_test_data/generated_tilesets')
        tiler.create_directory("tests/tileset_reader_test_data/generated_tilesets/basic_case/")

        reader = TilesetReader()
        tileset_1 = reader.read_tileset(path)
        tiler.link_tile_and_tileset(tileset_1, path)
        tileset_2 = tiler.from_tileset(tileset_1)
        tileset_2.write_to_directory("tests/tileset_reader_test_data/generated_tilesets/basic_case/")

    def test_merge(self):
        tiler = B3dmTiler()
        tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=True)
        path = "tests/tileset_reader_test_data/white_buildings/"
        merge = ["tests/tileset_reader_test_data/textured_cube/"]
        if not os.path.exists('tests/tileset_reader_test_data/generated_tilesets'):
            os.makedirs('tests/tileset_reader_test_data/generated_tilesets')
        tiler.create_directory("tests/tileset_reader_test_data/generated_tilesets/merge/")

        reader = TilesetReader()
        tileset_1 = reader.read_tileset(path)
        tiler.link_tile_and_tileset(tileset_1, path)

        if len(merge) > 0:
            tiler.merge_tilesets(tileset_1, merge)

        tileset_2 = tiler.from_tileset(tileset_1)
        tileset_2.write_to_directory("tests/tileset_reader_test_data/generated_tilesets/merge/")

    def test_transform(self):
        tiler = B3dmTiler()
        tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, -200], with_texture=True, scale=1.2)
        path = "tests/tileset_reader_test_data/white_buildings/"
        merge = ["tests/tileset_reader_test_data/textured_cube/"]
        if not os.path.exists('tests/tileset_reader_test_data/generated_tilesets'):
            os.makedirs('tests/tileset_reader_test_data/generated_tilesets')
        tiler.create_directory("tests/tileset_reader_test_data/generated_tilesets/transform/")

        reader = TilesetReader()
        tileset_1 = reader.read_tileset(path)
        tiler.link_tile_and_tileset(tileset_1, path)

        if len(merge) > 0:
            tiler.merge_tilesets(tileset_1, merge)

        tileset_2 = tiler.from_tileset(tileset_1)
        tileset_2.write_to_directory("tests/tileset_reader_test_data/generated_tilesets/transform/")

    def test_obj(self):
        tiler = B3dmTiler()
        obj = "tests/tileset_reader_test_data/generated_objs/output.obj"
        tiler.args = Namespace(obj=obj, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=True)
        path = "tests/tileset_reader_test_data/white_buildings/"
        merge = ["tests/tileset_reader_test_data/textured_cube/"]
        if not os.path.exists('tests/tileset_reader_test_data/generated_tilesets'):
            os.makedirs('tests/tileset_reader_test_data/generated_tilesets')
        if not os.path.exists('tests/tileset_reader_test_data/generated_objs'):
            os.makedirs('tests/tileset_reader_test_data/generated_objs')
        tiler.create_directory("tests/tileset_reader_test_data/generated_tilesets/obj/")

        reader = TilesetReader()
        tileset_1 = reader.read_tileset(path)
        tiler.link_tile_and_tileset(tileset_1, path)

        if len(merge) > 0:
            tiler.merge_tilesets(tileset_1, merge)

        tileset_2 = tiler.from_tileset(tileset_1)
        tileset_2.write_to_directory("tests/tileset_reader_test_data/generated_tilesets/obj/")
