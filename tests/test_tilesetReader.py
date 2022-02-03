import unittest
import os
from argparse import Namespace

from py3dtilers.TilesetReader.TilesetReader import TilesetTiler
from py3dtilers.TilesetReader.TilesetMerger import TilesetMerger


class Test_Tile(unittest.TestCase):

    def test_basic_case(self):
        tiler = TilesetTiler()
        tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False)
        paths = ["tests/tileset_reader_test_data/white_buildings/"]
        if not os.path.exists('tests/tileset_reader_test_data/generated_tilesets'):
            os.makedirs('tests/tileset_reader_test_data/generated_tilesets')
        tiler.create_directory("tests/tileset_reader_test_data/generated_tilesets/basic_case/")
        tileset = tiler.read_and_merge_tilesets(paths)
        tileset = tiler.transform_tileset(tileset)
        tileset.write_to_directory("tests/tileset_reader_test_data/generated_tilesets/basic_case/")

    def test_merge(self):
        tiler = TilesetTiler()
        tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=True)
        paths = ["tests/tileset_reader_test_data/white_buildings/", "tests/tileset_reader_test_data/textured_cube/"]
        if not os.path.exists('tests/tileset_reader_test_data/generated_tilesets'):
            os.makedirs('tests/tileset_reader_test_data/generated_tilesets')
        tiler.create_directory("tests/tileset_reader_test_data/generated_tilesets/merge/")
        tileset = tiler.read_and_merge_tilesets(paths)
        tileset = tiler.transform_tileset(tileset)
        tileset.write_to_directory("tests/tileset_reader_test_data/generated_tilesets/merge/")

    def test_transform(self):
        tiler = TilesetTiler()
        tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, -200], with_texture=True, scale=1.2)
        paths = ["tests/tileset_reader_test_data/white_buildings/", "tests/tileset_reader_test_data/textured_cube/"]
        if not os.path.exists('tests/tileset_reader_test_data/generated_tilesets'):
            os.makedirs('tests/tileset_reader_test_data/generated_tilesets')
        tiler.create_directory("tests/tileset_reader_test_data/generated_tilesets/transform/")
        tileset = tiler.read_and_merge_tilesets(paths)
        tileset = tiler.transform_tileset(tileset)
        tileset.write_to_directory("tests/tileset_reader_test_data/generated_tilesets/transform/")

    def test_obj(self):
        tiler = TilesetTiler()
        obj = "tests/tileset_reader_test_data/generated_objs/output.obj"
        tiler.args = Namespace(obj=obj, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=True)
        paths = ["tests/tileset_reader_test_data/white_buildings/", "tests/tileset_reader_test_data/textured_cube/"]
        if not os.path.exists('tests/tileset_reader_test_data/generated_tilesets'):
            os.makedirs('tests/tileset_reader_test_data/generated_tilesets')
        if not os.path.exists('tests/tileset_reader_test_data/generated_objs'):
            os.makedirs('tests/tileset_reader_test_data/generated_objs')
        tiler.create_directory("tests/tileset_reader_test_data/generated_tilesets/obj/")
        tileset = tiler.read_and_merge_tilesets(paths)
        tileset = tiler.transform_tileset(tileset)
        tileset.write_to_directory("tests/tileset_reader_test_data/generated_tilesets/obj/")

    def test_merger(self):
        merger = TilesetMerger(output_path="tests/tileset_reader_test_data/generated_tilesets/merger/")
        paths = ["tests/tileset_reader_test_data/white_buildings/", "tests/tileset_reader_test_data/textured_cube/"]
        tilesets = merger.reader.read_tilesets(paths)

        if not os.path.exists('tests/tileset_reader_test_data/generated_tilesets'):
            os.makedirs('tests/tileset_reader_test_data/generated_tilesets')
        tileset, root_tiles_paths = merger.merge_tilesets(tilesets, paths)
        merger.write_merged_tileset(tileset, root_tiles_paths)
