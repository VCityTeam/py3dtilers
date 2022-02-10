import unittest
import os
from argparse import Namespace

from py3dtilers.GeojsonTiler.GeojsonTiler import GeojsonTiler


class Test_Tile(unittest.TestCase):

    def test_basic_case(self):
        path = 'tests/geojson_tiler_test_data/buildings/feature_1/'
        obj_name = 'tests/geojson_tiler_test_data/generated_objs/block.obj'
        properties = ['height', 'HAUTEUR', 'prec', 'PREC_ALTI', 'z', 'NONE']
        directory = "tests/geojson_tiler_test_data/generated_tilesets/basic_case"
        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=obj_name, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=True)
        if(tileset is not None):
            tileset.write_to_directory(directory)

    def test_properties_with_other_name(self):
        path = 'tests/geojson_tiler_test_data/buildings/feature_2/'
        obj_name = 'tests/geojson_tiler_test_data/generated_objs/block_other_properties_name.obj'
        properties = ['height', 'HEIGHT', 'prec', 'NONE', 'z', 'NONE']
        directory = "tests/geojson_tiler_test_data/generated_tilesets/properties_with_other_name"
        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=obj_name, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=True)
        if(tileset is not None):
            tileset.write_to_directory(directory)

    def test_default_height(self):
        path = 'tests/geojson_tiler_test_data/buildings/feature_2/'
        obj_name = 'tests/geojson_tiler_test_data/generated_objs/block_default_height.obj'
        properties = ['height', '10', 'prec', 'NONE', 'z', 'NONE']
        directory = "tests/geojson_tiler_test_data/generated_tilesets/default_height"
        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=obj_name, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=True)
        if(tileset is not None):
            tileset.write_to_directory(directory)

    def test_z(self):
        path = 'tests/geojson_tiler_test_data/buildings/feature_2/'
        obj_name = 'tests/geojson_tiler_test_data/generated_objs/block_z.obj'
        properties = ['height', '10', 'prec', 'NONE', 'z', '300']
        directory = "tests/geojson_tiler_test_data/generated_tilesets/z"
        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=obj_name, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=True)
        if(tileset is not None):
            tileset.write_to_directory(directory)

    def test_no_height(self):
        path = 'tests/geojson_tiler_test_data/buildings/feature_2/'
        obj_name = 'tests/geojson_tiler_test_data/generated_objs/block_no_height.obj'
        properties = ['height', 'HAUTEUR', 'prec', 'NONE', 'z', 'NONE']
        directory = "tests/geojson_tiler_test_data/generated_tilesets/no_height"
        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=obj_name, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=True)
        if(tileset is not None):
            tileset.write_to_directory(directory)

    def test_add_color(self):
        path = 'tests/geojson_tiler_test_data/buildings/feature_1/'
        obj_name = 'tests/geojson_tiler_test_data/generated_objs/block_color.obj'
        properties = ['height', 'HAUTEUR', 'prec', 'NONE', 'z', 'NONE']
        directory = "tests/geojson_tiler_test_data/generated_tilesets/add_color"
        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=obj_name, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=True, color_attribute=('HAUTEUR', 'numeric'))
        if(tileset is not None):
            tileset.write_to_directory(directory)

    def test_create_loa(self):
        path = 'tests/geojson_tiler_test_data/buildings/feature_1/'
        properties = ['height', 'HAUTEUR', 'prec', 'PREC_ALTI', 'z', 'NONE']
        directory = "tests/geojson_tiler_test_data/generated_tilesets/create_loa"
        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=None, loa='tests/geojson_tiler_test_data/polygons/', lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=True)
        if(tileset is not None):
            tileset.write_to_directory(directory)

    def test_create_lod1(self):
        path = 'tests/geojson_tiler_test_data/buildings/feature_1/'
        properties = ['height', 'HAUTEUR', 'prec', 'PREC_ALTI', 'z', 'NONE']
        directory = "tests/geojson_tiler_test_data/generated_tilesets/create_lod1"
        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=None, loa=None, lod1=True, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=True)
        if(tileset is not None):
            tileset.write_to_directory(directory)

    def test_create_lod1_and_loa(self):
        path = 'tests/geojson_tiler_test_data/buildings/feature_1/'
        properties = ['height', 'HAUTEUR', 'prec', 'PREC_ALTI', 'z', 'NONE']
        directory = "tests/geojson_tiler_test_data/generated_tilesets/create_lod1_and_loa"
        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=None, loa='tests/geojson_tiler_test_data/polygons/', lod1=True, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=True)
        if(tileset is not None):
            tileset.write_to_directory(directory)

    def test_line_string(self):
        path = 'tests/geojson_tiler_test_data/roads/line_string_road.geojson'
        obj_name = 'tests/geojson_tiler_test_data/generated_objs/road_line_string.obj'
        properties = ['height', '1', 'width', '1', 'prec', 'NONE', 'z', 'NONE']
        directory = "tests/geojson_tiler_test_data/generated_tilesets/line_string"
        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=obj_name, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=False)
        if(tileset is not None):
            tileset.write_to_directory(directory)

    def test_multi_line_string(self):
        path = 'tests/geojson_tiler_test_data/roads/multi_line_string_road.geojson'
        obj_name = 'tests/geojson_tiler_test_data/generated_objs/road_multi_line_string.obj'
        properties = ['height', '1', 'width', '1', 'prec', 'NONE', 'z', 'NONE']
        directory = "tests/geojson_tiler_test_data/generated_tilesets/multi_line_string"
        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=obj_name, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=False)
        if(tileset is not None):
            tileset.write_to_directory(directory)


if __name__ == '__main__':
    unittest.main()
