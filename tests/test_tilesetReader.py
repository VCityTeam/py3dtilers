import unittest
from argparse import Namespace
from pathlib import Path

from py3dtilers.TilesetReader.TilesetReader import TilesetTiler
from py3dtilers.TilesetReader.TilesetMerger import TilesetMerger


class Test_Tile(unittest.TestCase):

    def test_basic_case(self):
        tiler = TilesetTiler()
        tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False)
        paths = [Path("tests/tileset_reader_test_data/white_buildings/")]

        tileset = tiler.read_and_merge_tilesets(paths)
        tileset = tiler.transform_tileset(tileset)
        tileset.write_to_directory(Path("tests/tileset_reader_test_data/generated_tilesets/basic_case/"))

    def test_merge(self):
        tiler = TilesetTiler()
        tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=True)
        paths = [Path("tests/tileset_reader_test_data/white_buildings/"), Path("tests/tileset_reader_test_data/textured_cube/")]

        tileset = tiler.read_and_merge_tilesets(paths)
        tileset = tiler.transform_tileset(tileset)
        tileset.write_to_directory(Path("tests/tileset_reader_test_data/generated_tilesets/merge/"))

    def test_transform(self):
        tiler = TilesetTiler()
        tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, -200], with_texture=True, scale=1.2)
        paths = [Path("tests/tileset_reader_test_data/white_buildings/"), Path("tests/tileset_reader_test_data/textured_cube/")]

        tileset = tiler.read_and_merge_tilesets(paths)
        tileset = tiler.transform_tileset(tileset)
        tileset.write_to_directory(Path("tests/tileset_reader_test_data/generated_tilesets/transform/"))

    def test_obj(self):
        tiler = TilesetTiler()
        obj = "tests/tileset_reader_test_data/generated_objs/output.obj"
        tiler.args = Namespace(obj=obj, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=True)
        paths = [Path("tests/tileset_reader_test_data/white_buildings/"), Path("tests/tileset_reader_test_data/textured_cube/")]

        tileset = tiler.read_and_merge_tilesets(paths)
        tileset = tiler.transform_tileset(tileset)
        tileset.write_to_directory(Path("tests/tileset_reader_test_data/generated_tilesets/obj/"))

    def test_merger(self):
        merger = TilesetMerger(output_path="tests/tileset_reader_test_data/generated_tilesets/merger/")
        paths = [Path("tests/tileset_reader_test_data/white_buildings/"), Path("tests/tileset_reader_test_data/textured_cube/")]
        tilesets = merger.reader.read_tilesets(paths)

        tileset, root_tiles_paths = merger.merge_tilesets(tilesets, paths)
        merger.write_merged_tileset(tileset, root_tiles_paths)
