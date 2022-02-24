import unittest
from argparse import Namespace
from pathlib import Path

from py3dtilers.CityTiler.citym_building import CityMBuildings
from py3dtilers.CityTiler.citym_relief import CityMReliefs
from py3dtilers.CityTiler.citym_waterbody import CityMWaterBodies
from py3dtilers.CityTiler.citym_bridge import CityMBridges
from py3dtilers.CityTiler.database_accesses import open_data_base
from py3dtilers.CityTiler.CityTiler import CityTiler


class Test_Tile(unittest.TestCase):

    def test_building_basic_case(self):

        directory = Path("tests/city_tiler_test_data/generated_tilesets/building_basic_case")
        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMBuildings
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory, split_surfaces=False)
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_to_directory(directory)
        cursor.close()

    def test_water_basic_case(self):

        directory = Path("tests/city_tiler_test_data/generated_tilesets/water_basic_case")
        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMWaterBodies
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory, split_surfaces=False)
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_to_directory(directory)
        cursor.close()

    def test_relief_basic_case(self):

        directory = Path("tests/city_tiler_test_data/generated_tilesets/relief_basic_case")
        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMReliefs
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory, split_surfaces=False)
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_to_directory(directory)
        cursor.close()

    def test_building_lod1(self):

        directory = Path("tests/city_tiler_test_data/generated_tilesets/building_lod1")
        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMReliefs
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = Namespace(obj=None, loa=None, lod1=True, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory, split_surfaces=False)
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_to_directory(directory)
        cursor.close()

    def test_building_loa(self):

        directory = Path("tests/city_tiler_test_data/generated_tilesets/building_loa")
        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMBuildings
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = Namespace(obj=None, loa="tests/city_tiler_test_data/polygons", lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory, split_surfaces=False)
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_to_directory(directory)
        cursor.close()

    def test_building_loa_lod1(self):

        directory = Path("tests/city_tiler_test_data/generated_tilesets/building_loa_lod1")
        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMBuildings
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = Namespace(obj=None, loa="tests/city_tiler_test_data/polygons", lod1=True, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory, split_surfaces=False)
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_to_directory(directory)
        cursor.close()

    def test_building_BTH(self):

        directory = Path("tests/city_tiler_test_data/generated_tilesets/building_BTH")
        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMBuildings
        CityMBuildings.set_bth()
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory, split_surfaces=False)
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_to_directory(directory)
        CityMBuildings.with_bth = False
        cursor.close()

    def test_building_split_surface(self):

        directory = Path("tests/city_tiler_test_data/generated_tilesets/building_split_surface")
        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMBuildings
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory, split_surfaces=True)
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_to_directory(directory)
        cursor.close()

    def test_relief_split_surface(self):

        directory = Path("tests/city_tiler_test_data/generated_tilesets/relief_split_surface")
        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMReliefs
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory, split_surfaces=True)
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_to_directory(directory)
        cursor.close()

    def test_water_split_surface(self):

        directory = Path("tests/city_tiler_test_data/generated_tilesets/water_split_surface")
        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMWaterBodies
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory, split_surfaces=True)
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_to_directory(directory)
        cursor.close()

    def test_building_texture(self):

        directory = Path("tests/city_tiler_test_data/generated_tilesets/building_texture")
        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMBuildings
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=True, output_dir=directory, split_surfaces=False)
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_to_directory(directory)
        cursor.close()

    def test_relief_texture(self):

        directory = Path("tests/city_tiler_test_data/generated_tilesets/relief_texture")
        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMReliefs
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=True, output_dir=directory, split_surfaces=False)
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_to_directory(directory)
        cursor.close()

    def test_bridge(self):

        directory = Path("tests/city_tiler_test_data/generated_tilesets/bridge_basic_case")
        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMBridges
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory, split_surfaces=False)
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_to_directory(directory)
        cursor.close()

    def test_bridge_split_surface(self):

        directory = Path("tests/city_tiler_test_data/generated_tilesets/bridge_split_surface")
        cursor = open_data_base(Path("tests/city_tiler_test_data/test_config.yml"))
        objects_type = CityMBridges
        objects_type.set_cursor(cursor)
        city_tiler = CityTiler()
        city_tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory, split_surfaces=True)
        tileset = city_tiler.from_3dcitydb(cursor, objects_type)

        tileset.write_to_directory(directory)
        cursor.close()


if __name__ == '__main__':
    unittest.main()
