import unittest
import os
from argparse import Namespace

from py3dtilers.GeojsonTiler.GeojsonTiler import GeojsonTiler


class Test_Tile(unittest.TestCase):

    def test_basic_case(self):
        path = 'tests/geojson_tiler_test_data/buildings/feature_1/'
        obj_name = 'tests/geojson_tiler_test_data/generated_objs/block.obj'
        properties = ['height', 'HAUTEUR', 'prec', 'PREC_ALTI', 'z', 'NONE']

        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=obj_name, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=True)
        if(tileset is not None):

            folder_name = "basic_case"
            print("tileset in tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)
            tileset.write_to_directory("tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)

    def test_properties_with_other_name(self):
        path = 'tests/geojson_tiler_test_data/buildings/feature_2/'
        obj_name = 'tests/geojson_tiler_test_data/generated_objs/block_other_properties_name.obj'
        properties = ['height', 'HEIGHT', 'prec', 'NONE', 'z', 'NONE']

        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=obj_name, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=True)
        if(tileset is not None):

            folder_name = "properties_with_other_name"
            print("tileset in tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)
            tileset.write_to_directory("tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)

    def test_default_height(self):
        path = 'tests/geojson_tiler_test_data/buildings/feature_2/'
        obj_name = 'tests/geojson_tiler_test_data/generated_objs/block_default_height.obj'
        properties = ['height', '10', 'prec', 'NONE', 'z', 'NONE']

        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=obj_name, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=True)
        if(tileset is not None):

            folder_name = "default_height"
            print("tileset in tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)
            tileset.write_to_directory("tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)

    def test_z(self):
        path = 'tests/geojson_tiler_test_data/buildings/feature_2/'
        obj_name = 'tests/geojson_tiler_test_data/generated_objs/block_z.obj'
        properties = ['height', '10', 'prec', 'NONE', 'z', '300']

        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=obj_name, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=True)
        if(tileset is not None):

            folder_name = "z"
            print("tileset in tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)
            tileset.write_to_directory("tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)

    def test_no_height(self):
        path = 'tests/geojson_tiler_test_data/buildings/feature_2/'
        obj_name = 'tests/geojson_tiler_test_data/generated_objs/block_no_height.obj'
        properties = ['height', 'HAUTEUR', 'prec', 'NONE', 'z', 'NONE']

        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=obj_name, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=True)
        if(tileset is not None):

            folder_name = "no_height"
            print("tileset in tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)
            tileset.write_to_directory("tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)

    def test_add_color(self):
        path = 'tests/geojson_tiler_test_data/buildings/feature_1/'
        obj_name = 'tests/geojson_tiler_test_data/generated_objs/block_color.obj'
        properties = ['height', 'HAUTEUR', 'prec', 'NONE', 'z', 'NONE']

        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=obj_name, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=True, color_attribute=('HAUTEUR', 'numeric'))
        if(tileset is not None):

            folder_name = "add_color"
            print("tileset in tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)
            tileset.write_to_directory("tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)

    def test_create_loa(self):
        path = 'tests/geojson_tiler_test_data/buildings/feature_1/'
        properties = ['height', 'HAUTEUR', 'prec', 'PREC_ALTI', 'z', 'NONE']

        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=None, loa='tests/geojson_tiler_test_data/polygons/', lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=True)
        if(tileset is not None):

            folder_name = "create_loa"
            print("tileset in tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)
            tileset.write_to_directory("tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)

    def test_create_lod1(self):
        path = 'tests/geojson_tiler_test_data/buildings/feature_1/'
        properties = ['height', 'HAUTEUR', 'prec', 'PREC_ALTI', 'z', 'NONE']

        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=None, loa=None, lod1=True, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=True)
        if(tileset is not None):

            folder_name = "create_lod1"
            print("tileset in tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)
            tileset.write_to_directory("tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)

    def test_create_lod1_and_loa(self):
        path = 'tests/geojson_tiler_test_data/buildings/feature_1/'
        properties = ['height', 'HAUTEUR', 'prec', 'PREC_ALTI', 'z', 'NONE']

        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=None, loa='tests/geojson_tiler_test_data/polygons/', lod1=True, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=True)
        if(tileset is not None):

            folder_name = "create_lod1"
            print("tileset in tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)
            tileset.write_to_directory("tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)

    def test_line_string(self):
        path = 'tests/geojson_tiler_test_data/roads/line_string_road.geojson'
        obj_name = 'tests/geojson_tiler_test_data/generated_objs/road_line_string.obj'
        properties = ['height', '1', 'width', '1', 'prec', 'NONE', 'z', 'NONE']

        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=obj_name, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=False)
        if(tileset is not None):

            folder_name = "line_string"
            print("tileset in tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)
            tileset.write_to_directory("tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)

    def test_multi_line_string(self):
        path = 'tests/geojson_tiler_test_data/roads/multi_line_string_road.geojson'
        obj_name = 'tests/geojson_tiler_test_data/generated_objs/road_multi_line_string.obj'
        properties = ['height', '1', 'width', '1', 'prec', 'NONE', 'z', 'NONE']

        if not os.path.exists('tests/geojson_tiler_test_data/generated_objs'):
            os.makedirs('tests/geojson_tiler_test_data/generated_objs')
        if not os.path.exists('tests/geojson_tiler_test_data/generated_tilesets'):
            os.makedirs('tests/geojson_tiler_test_data/generated_tilesets')

        geojson_tiler = GeojsonTiler()
        geojson_tiler.args = Namespace(obj=obj_name, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False)
        tileset = geojson_tiler.from_geojson_directory(path, properties, is_roof=False)
        if(tileset is not None):

            folder_name = "multi_line_string"
            print("tileset in tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)
            tileset.write_to_directory("tests/geojson_tiler_test_data/generated_tilesets/" + folder_name)


if __name__ == '__main__':
    unittest.main()
