import unittest
from argparse import Namespace
from pathlib import Path

from py3dtilers.GeojsonTiler.GeojsonTiler import GeojsonTiler


def get_default_namespace():
    return Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946',
                     crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, scale=1,
                     output_dir=None, geometric_error=[None, None, None], kd_tree_max=None,
                     texture_lods=0, keep_ids=[], exclude_ids=[], no_normals=False, as_lods=False)


class Test_Tile(unittest.TestCase):

    def test_basic_case(self):
        properties = ['height', 'HAUTEUR', 'prec', 'PREC_ALTI', 'z', 'NONE']

        geojson_tiler = GeojsonTiler()
        geojson_tiler.files = [Path('tests/geojson_tiler_test_data/buildings/feature_1/oneBlock.geojson')]
        geojson_tiler.args = get_default_namespace()
        geojson_tiler.args.output_dir = Path("tests/geojson_tiler_test_data/generated_tilesets/basic_case")
        geojson_tiler.args.obj = Path('tests/geojson_tiler_test_data/generated_objs/block.obj')
        tileset = geojson_tiler.from_geojson_directory(properties, is_roof=True)
        if tileset is not None:
            tileset.write_as_json(geojson_tiler.args.output_dir)

    def test_properties_with_other_name(self):
        properties = ['height', 'HEIGHT', 'prec', 'NONE', 'z', 'NONE']

        geojson_tiler = GeojsonTiler()
        geojson_tiler.files = [Path('tests/geojson_tiler_test_data/buildings/feature_2/oneBlock.geojson')]
        geojson_tiler.args = get_default_namespace()
        geojson_tiler.args.output_dir = Path("tests/geojson_tiler_test_data/generated_tilesets/properties_with_other_name")
        geojson_tiler.args.obj = Path('tests/geojson_tiler_test_data/generated_objs/block_other_properties_name.obj')
        tileset = geojson_tiler.from_geojson_directory(properties, is_roof=True)
        if tileset is not None:
            tileset.write_as_json(geojson_tiler.args.output_dir)

    def test_default_height(self):
        properties = ['height', '10', 'prec', 'NONE', 'z', 'NONE']

        geojson_tiler = GeojsonTiler()
        geojson_tiler.files = [Path('tests/geojson_tiler_test_data/buildings/feature_2/oneBlock.geojson')]
        geojson_tiler.args = get_default_namespace()
        geojson_tiler.args.output_dir = Path("tests/geojson_tiler_test_data/generated_tilesets/default_height")
        geojson_tiler.args.obj = Path('tests/geojson_tiler_test_data/generated_objs/block_default_height.obj')
        tileset = geojson_tiler.from_geojson_directory(properties, is_roof=True)
        if tileset is not None:
            tileset.write_as_json(geojson_tiler.args.output_dir)

    def test_z(self):
        properties = ['height', '10', 'prec', 'NONE', 'z', '300']

        geojson_tiler = GeojsonTiler()
        geojson_tiler.files = [Path('tests/geojson_tiler_test_data/buildings/feature_2/oneBlock.geojson')]
        geojson_tiler.args = get_default_namespace()
        geojson_tiler.args.output_dir = Path("tests/geojson_tiler_test_data/generated_tilesets/z")
        geojson_tiler.args.obj = Path('tests/geojson_tiler_test_data/generated_objs/block_z.obj')
        tileset = geojson_tiler.from_geojson_directory(properties, is_roof=True)
        if tileset is not None:
            tileset.write_as_json(geojson_tiler.args.output_dir)

    def test_no_height(self):
        properties = ['height', 'HAUTEUR', 'prec', 'NONE', 'z', 'NONE']

        geojson_tiler = GeojsonTiler()
        geojson_tiler.files = [Path('tests/geojson_tiler_test_data/buildings/feature_2/oneBlock.geojson')]
        geojson_tiler.args = get_default_namespace()
        geojson_tiler.args.output_dir = Path("tests/geojson_tiler_test_data/generated_tilesets/no_height")
        geojson_tiler.args.obj = Path('tests/geojson_tiler_test_data/generated_objs/block_no_height.obj')
        tileset = geojson_tiler.from_geojson_directory(properties, is_roof=True)
        if tileset is not None:
            tileset.write_as_json(geojson_tiler.args.output_dir)

    def test_add_color(self):
        properties = ['height', 'HAUTEUR', 'prec', 'NONE', 'z', 'NONE']

        geojson_tiler = GeojsonTiler()
        geojson_tiler.files = [Path('tests/geojson_tiler_test_data/buildings/feature_1/oneBlock.geojson')]
        geojson_tiler.args = get_default_namespace()
        geojson_tiler.args.output_dir = Path("tests/geojson_tiler_test_data/generated_tilesets/add_color")
        geojson_tiler.args.obj = Path('tests/geojson_tiler_test_data/generated_objs/block_color.obj')
        tileset = geojson_tiler.from_geojson_directory(properties, is_roof=True, color_attribute=('HAUTEUR', 'numeric'))
        if tileset is not None:
            tileset.write_as_json(geojson_tiler.args.output_dir)

    def test_create_loa(self):
        properties = ['height', 'HAUTEUR', 'prec', 'PREC_ALTI', 'z', 'NONE']

        geojson_tiler = GeojsonTiler()
        geojson_tiler.files = [Path('tests/geojson_tiler_test_data/buildings/feature_1/oneBlock.geojson')]
        geojson_tiler.args = get_default_namespace()
        geojson_tiler.args.output_dir = Path("tests/geojson_tiler_test_data/generated_tilesets/create_loa")
        geojson_tiler.args.loa = Path('tests/geojson_tiler_test_data/polygons/')
        tileset = geojson_tiler.from_geojson_directory(properties, is_roof=True)
        if tileset is not None:
            tileset.write_as_json(geojson_tiler.args.output_dir)

    def test_create_lod1(self):
        properties = ['height', 'HAUTEUR', 'prec', 'PREC_ALTI', 'z', 'NONE']

        geojson_tiler = GeojsonTiler()
        geojson_tiler.files = [Path('tests/geojson_tiler_test_data/buildings/feature_1/oneBlock.geojson')]
        geojson_tiler.args = get_default_namespace()
        geojson_tiler.args.output_dir = Path("tests/geojson_tiler_test_data/generated_tilesets/create_lod1")
        geojson_tiler.args.lod1 = True
        tileset = geojson_tiler.from_geojson_directory(properties, is_roof=True)
        if tileset is not None:
            tileset.write_as_json(geojson_tiler.args.output_dir)

    def test_create_lod1_and_loa(self):
        properties = ['height', 'HAUTEUR', 'prec', 'PREC_ALTI', 'z', 'NONE']

        geojson_tiler = GeojsonTiler()
        geojson_tiler.files = [Path('tests/geojson_tiler_test_data/buildings/feature_1/oneBlock.geojson')]
        geojson_tiler.args = get_default_namespace()
        geojson_tiler.args.output_dir = Path("tests/geojson_tiler_test_data/generated_tilesets/create_lod1_and_loa")
        geojson_tiler.args.loa = Path('tests/geojson_tiler_test_data/polygons/')
        geojson_tiler.args.lod1 = True
        tileset = geojson_tiler.from_geojson_directory(properties, is_roof=True)
        if tileset is not None:
            tileset.write_as_json(geojson_tiler.args.output_dir)

    def test_line_string(self):
        properties = ['height', '1', 'width', '1', 'prec', 'NONE', 'z', 'NONE']

        geojson_tiler = GeojsonTiler()
        geojson_tiler.files = [Path('tests/geojson_tiler_test_data/roads/line_string_road.geojson')]
        geojson_tiler.args = get_default_namespace()
        geojson_tiler.args.output_dir = Path("tests/geojson_tiler_test_data/generated_tilesets/line_string")
        geojson_tiler.args.obj = Path('tests/geojson_tiler_test_data/generated_objs/road_line_string.obj')
        tileset = geojson_tiler.from_geojson_directory(properties, is_roof=False)
        if tileset is not None:
            tileset.write_as_json(geojson_tiler.args.output_dir)

    def test_multi_line_string(self):
        properties = ['height', '1', 'width', '1', 'prec', 'NONE', 'z', 'NONE']

        geojson_tiler = GeojsonTiler()
        geojson_tiler.files = [Path('tests/geojson_tiler_test_data/roads/multi_line_string_road.geojson')]
        geojson_tiler.args = get_default_namespace()
        geojson_tiler.args.output_dir = Path("tests/geojson_tiler_test_data/generated_tilesets/multi_line_string")
        geojson_tiler.args.obj = Path('tests/geojson_tiler_test_data/generated_objs/road_multi_line_string.obj')
        tileset = geojson_tiler.from_geojson_directory(properties, is_roof=False)
        if tileset is not None:
            tileset.write_as_json(geojson_tiler.args.output_dir)

    def test_keep_properties(self):
        properties = ['height', 'HAUTEUR', 'prec', 'PREC_ALTI', 'z', 'NONE']

        geojson_tiler = GeojsonTiler()
        geojson_tiler.files = [Path('tests/geojson_tiler_test_data/buildings/feature_1/oneBlock.geojson')]
        geojson_tiler.args = get_default_namespace()
        geojson_tiler.args.output_dir = Path("tests/geojson_tiler_test_data/generated_tilesets/keep_props")
        geojson_tiler.args.obj = Path('tests/geojson_tiler_test_data/generated_objs/block_keep_props.obj')
        tileset = geojson_tiler.from_geojson_directory(properties, is_roof=True, keep_properties=True)
        if tileset is not None:
            tileset.write_as_json(geojson_tiler.args.output_dir)


if __name__ == '__main__':
    unittest.main()
