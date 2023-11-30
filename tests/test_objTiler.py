import unittest
from argparse import Namespace
from pathlib import Path

from py3dtilers.ObjTiler.ObjTiler import ObjTiler


def get_default_namespace():
    return Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946',
                     crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, scale=1,
                     output_dir=None, geometric_error=[None, None, None], kd_tree_max=None,
                     texture_lods=0, keep_ids=[], exclude_ids=[], no_normals=False, as_lods=False)


class Test_Tile(unittest.TestCase):

    def test_basic_case(self):
        obj_tiler = ObjTiler()
        obj_tiler.files = [Path('tests/obj_tiler_data/Cube/cube_1.obj'), Path('tests/obj_tiler_data/Cube/cube_2.obj')]
        obj_tiler.args = get_default_namespace()
        obj_tiler.args.output_dir = Path("tests/obj_tiler_data/generated_tilesets/basic_case")

        tileset = obj_tiler.from_obj_directory()
        if tileset is not None:
            tileset.write_as_json(Path(obj_tiler.args.output_dir))

    def test_basic_case_no_normals(self):
        obj_tiler = ObjTiler()
        obj_tiler.files = [Path('tests/obj_tiler_data/Cube/cube_1.obj'), Path('tests/obj_tiler_data/Cube/cube_2.obj')]
        obj_tiler.args = get_default_namespace()
        obj_tiler.args.output_dir = Path("tests/obj_tiler_data/generated_tilesets/basic_case_no_normals")
        obj_tiler.args.no_normals = True

        tileset = obj_tiler.from_obj_directory()
        if tileset is not None:
            tileset.write_as_json(Path(obj_tiler.args.output_dir))

    def test_basic_case_height_mult(self):
        obj_tiler = ObjTiler()
        obj_tiler.files = [Path('tests/obj_tiler_data/Cube/cube_1.obj'), Path('tests/obj_tiler_data/Cube/cube_2.obj')]
        obj_tiler.args = get_default_namespace()
        obj_tiler.args.output_dir = Path("tests/obj_tiler_data/generated_tilesets/basic_case_height_mult")
        obj_tiler.args.height_mult = 0.3048006096

        tileset = obj_tiler.from_obj_directory()
        if tileset is not None:
            tileset.write_as_json(Path(obj_tiler.args.output_dir))

    def test_texture(self):
        obj_tiler = ObjTiler()
        obj_tiler.files = [Path('tests/obj_tiler_data/TexturedCube/cube.obj')]
        obj_tiler.args = get_default_namespace()
        obj_tiler.args.output_dir = Path("tests/obj_tiler_data/generated_tilesets/texture")
        obj_tiler.args.offset = [1843397, 5173891, 300]  # Arbitrary offset to place the 3DTiles in Lyon city
        obj_tiler.args.with_texture = True
        obj_tiler.args.scale = 50

        tileset = obj_tiler.from_obj_directory()
        if tileset is not None:
            tileset.write_as_json(Path(obj_tiler.args.output_dir))

    def test_texture_lods(self):
        obj_tiler = ObjTiler()
        obj_tiler.files = [Path('tests/obj_tiler_data/TexturedCube/cube.obj')]
        obj_tiler.args = get_default_namespace()
        obj_tiler.args.output_dir = Path("tests/obj_tiler_data/generated_tilesets/texture_lods")
        obj_tiler.args.offset = [1843397, 5173891, 300]  # Arbitrary offset to place the 3DTiles in Lyon city
        obj_tiler.args.with_texture = True
        obj_tiler.args.scale = 50
        obj_tiler.args.texture_lods = 5

        tileset = obj_tiler.from_obj_directory()
        if tileset is not None:
            tileset.write_as_json(Path(obj_tiler.args.output_dir))

    def test_model_lods(self):
        obj_tiler = ObjTiler()
        obj_tiler.files = [Path('tests/obj_tiler_data/MultiLODModel/tour_part_dieu_2.obj'),
                           Path('tests/obj_tiler_data/MultiLODModel/tour_part_dieu_1.obj'),
                           Path('tests/obj_tiler_data/MultiLODModel/tour_part_dieu_0.obj')]
        obj_tiler.args = get_default_namespace()
        obj_tiler.args.output_dir = Path("tests/obj_tiler_data/generated_tilesets/multi_lods")
        obj_tiler.args.offset = [1843397, 5173891, 300]  # Arbitrary offset to place the 3DTiles in Lyon city
        obj_tiler.args.as_lods = True
        obj_tiler.args.geometric_error = [1, 5, 13]

        tileset = obj_tiler.from_obj_directory()
        if tileset is not None:
            tileset.write_as_json(Path(obj_tiler.args.output_dir))


if __name__ == '__main__':
    unittest.main()
