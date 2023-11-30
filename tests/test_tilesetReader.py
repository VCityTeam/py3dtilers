import unittest
from argparse import Namespace
from pathlib import Path

from py3dtilers.TilesetReader.TilesetReader import TilesetTiler
from py3dtilers.TilesetReader.TilesetMerger import TilesetMerger


def get_default_namespace():
    return Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946',
                     crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, scale=1,
                     output_dir=None, geometric_error=[None, None, None], kd_tree_max=None,
                     texture_lods=0, as_lods=False)


class Test_Tile(unittest.TestCase):

    def test_basic_case(self):
        tiler = TilesetTiler()
        tiler.args = get_default_namespace()
        tiler.args.output_dir = Path("tests/tileset_reader_test_data/generated_tilesets/basic_case/")
        tiler.files = [Path("tests/tileset_reader_test_data/white_buildings/")]

        tileset = tiler.read_and_merge_tilesets()
        tileset = tiler.transform_tileset(tileset)
        tileset.write_as_json(tiler.args.output_dir)

    def test_merge(self):
        tiler = TilesetTiler()
        tiler.args = get_default_namespace()
        tiler.args.output_dir = Path("tests/tileset_reader_test_data/generated_tilesets/merge/")
        tiler.files = [Path("tests/tileset_reader_test_data/white_buildings/"), Path("tests/tileset_reader_test_data/textured_cube/")]

        tileset = tiler.read_and_merge_tilesets()
        tileset = tiler.transform_tileset(tileset)
        tileset.write_as_json(tiler.args.output_dir)

    def test_texture(self):
        tiler = TilesetTiler()
        tiler.args = get_default_namespace()
        tiler.args.output_dir = Path("tests/tileset_reader_test_data/generated_tilesets/texture/")
        tiler.args.with_texture = True
        tiler.files = [Path("tests/tileset_reader_test_data/white_buildings/"), Path("tests/tileset_reader_test_data/textured_cube/")]

        tileset = tiler.read_and_merge_tilesets()
        tileset = tiler.transform_tileset(tileset)
        tileset.write_as_json(tiler.args.output_dir)

    def test_transform(self):
        tiler = TilesetTiler()
        tiler.args = get_default_namespace()
        tiler.args.output_dir = Path("tests/tileset_reader_test_data/generated_tilesets/transform/")
        tiler.args.offset = [0, 0, -200]
        tiler.args.scale = 1.2
        tiler.files = [Path("tests/tileset_reader_test_data/white_buildings/"), Path("tests/tileset_reader_test_data/textured_cube/")]

        tileset = tiler.read_and_merge_tilesets()
        tileset = tiler.transform_tileset(tileset)
        tileset.write_as_json(tiler.args.output_dir)

    def test_obj(self):
        tiler = TilesetTiler()
        tiler.args = get_default_namespace()
        tiler.args.output_dir = Path("tests/tileset_reader_test_data/generated_tilesets/obj/")
        tiler.args.obj = "tests/tileset_reader_test_data/generated_objs/output.obj"
        tiler.files = [Path("tests/tileset_reader_test_data/white_buildings/"), Path("tests/tileset_reader_test_data/textured_cube/")]

        tileset = tiler.read_and_merge_tilesets()
        tileset = tiler.transform_tileset(tileset)
        tileset.write_as_json(tiler.args.output_dir)

    def test_geometric_error(self):
        tiler = TilesetTiler()
        tiler.args = get_default_namespace()
        tiler.args.output_dir = Path("tests/tileset_reader_test_data/generated_tilesets/geometric_error/")
        tiler.args.geometric_error = [3, None, 100]
        tiler.files = [Path("tests/tileset_reader_test_data/white_buildings_with_lods/"), Path("tests/tileset_reader_test_data/textured_cube/")]

        tileset = tiler.read_and_merge_tilesets()
        tileset = tiler.transform_tileset(tileset)
        tileset.write_as_json(tiler.args.output_dir)

    def test_merger(self):
        merger = TilesetMerger(output_path="tests/tileset_reader_test_data/generated_tilesets/merger/")
        paths = [Path("tests/tileset_reader_test_data/white_buildings/"), Path("tests/tileset_reader_test_data/textured_cube/")]
        tilesets = merger.reader.read_tilesets(paths)

        tileset, root_tiles_paths = merger.merge_tilesets(tilesets, paths)
        merger.write_merged_tileset(tileset, root_tiles_paths)
