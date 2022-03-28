import unittest
from argparse import Namespace
from pathlib import Path

from py3dtilers.ObjTiler.ObjTiler import ObjTiler


def get_default_namespace():
    return Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946',
                     crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, scale=1,
                     output_dir=None, geometric_error=[None, None, None])


class Test_Tile(unittest.TestCase):

    def test_basic_case(self):
        path = Path('tests/obj_tiler_data/Cube')
        obj_tiler = ObjTiler()
        obj_tiler.current_path = "basic_case"
        obj_tiler.args = get_default_namespace()
        obj_tiler.args.output_dir = Path("tests/obj_tiler_data/generated_tilesets/")

        tileset = obj_tiler.from_obj_directory(path)
        if(tileset is not None):
            tileset.write_as_json(Path(obj_tiler.args.output_dir, obj_tiler.current_path))

    def test_texture(self):
        path = Path('tests/obj_tiler_data/TexturedCube')
        obj_tiler = ObjTiler()
        obj_tiler.current_path = "texture"
        obj_tiler.args = get_default_namespace()
        obj_tiler.args.output_dir = Path("tests/obj_tiler_data/generated_tilesets/")
        obj_tiler.args.offset = [-1843397, -5173891, -300]  # Arbitrary offset to place the 3DTiles in Lyon city
        obj_tiler.args.with_texture = True
        obj_tiler.args.scale = 50

        tileset = obj_tiler.from_obj_directory(path)
        if(tileset is not None):
            tileset.write_as_json(Path(obj_tiler.args.output_dir, obj_tiler.current_path))


if __name__ == '__main__':
    unittest.main()
