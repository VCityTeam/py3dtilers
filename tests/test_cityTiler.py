import unittest
from argparse import Namespace
from pathlib import Path

from py3dtilers.CityTiler.citym_building import CityMBuildings
from py3dtilers.CityTiler.citym_relief import CityMReliefs
from py3dtilers.CityTiler.citym_waterbody import CityMWaterBodies
from py3dtilers.CityTiler.citym_bridge import CityMBridges
from py3dtilers.CityTiler.database_accesses import open_data_base
from py3dtilers.CityTiler.CityTiler import CityTiler


def get_default_namespace():
    return Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946',
                     crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, scale=1,
                     output_dir=None, geometric_error=[None, None, None],
                     split_surfaces=False, add_color=False)


class Test_Tile(unittest.TestCase):

    def test_building_basic_case(self):

        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMBuildings
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/building_basic_case")
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)
        cursor.close()

    def test_water_basic_case(self):

        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMWaterBodies
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/water_basic_case")
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)
        cursor.close()

    def test_relief_basic_case(self):

        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMReliefs
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/relief_basic_case")
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)
        cursor.close()

    def test_building_lod1(self):

        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMReliefs
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/building_lod1")
        city_tiler.args.lod1 = True
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)
        cursor.close()

    def test_building_loa(self):

        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMBuildings
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/building_loa")
        city_tiler.args.loa = Path("tests/city_tiler_test_data/polygons")
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)
        cursor.close()

    def test_building_loa_lod1(self):

        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMBuildings
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/building_loa_lod1")
        city_tiler.args.loa = Path("tests/city_tiler_test_data/polygons")
        city_tiler.args.lod1 = True
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)
        cursor.close()

    def test_building_BTH(self):

        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMBuildings
        CityMBuildings.set_bth()
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/building_BTH")
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)
        CityMBuildings.with_bth = False
        cursor.close()

    def test_building_split_surface(self):

        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMBuildings
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/building_split_surface")
        city_tiler.args.split_surfaces = True
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)
        cursor.close()

    def test_relief_split_surface(self):

        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMReliefs
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/relief_split_surface")
        city_tiler.args.split_surfaces = True
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)
        cursor.close()

    def test_water_split_surface(self):

        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMWaterBodies
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/water_split_surface")
        city_tiler.args.split_surfaces = True
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)
        cursor.close()

    def test_building_texture(self):

        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMBuildings
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/building_texture")
        city_tiler.args.with_texture = True
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)
        cursor.close()

    def test_relief_texture(self):

        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMReliefs
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/relief_texture")
        city_tiler.args.with_texture = True
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)
        cursor.close()

    def test_bridge(self):

        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMBridges
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/bridge_basic_case")
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)
        cursor.close()

    def test_bridge_split_surface(self):

        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMBridges
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/bridge_split_surface")
        city_tiler.args.split_surfaces = True
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)
        cursor.close()

    def test_building_color(self):

        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMBuildings
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/building_color")
        city_tiler.args.add_color = True
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)
        cursor.close()


if __name__ == '__main__':
    unittest.main()
