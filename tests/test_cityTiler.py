import unittest
import pathlib

from py3dtiles import BoundingVolumeBox
from py3dtilers.Texture.texture import Texture
from py3dtilers.CityTiler.citym_building import CityMBuildings
from py3dtilers.CityTiler.citym_relief import CityMReliefs
from py3dtilers.CityTiler.citym_waterbody import CityMWaterBodies
from py3dtilers.CityTiler.database_accesses import open_data_base
from py3dtilers.CityTiler.CityTiler import from_3dcitydb


def create_directory(directory):
    target_dir = pathlib.Path(directory).expanduser()
    pathlib.Path(target_dir).mkdir(parents=True, exist_ok=True)
    target_dir = pathlib.Path(directory + '/tiles').expanduser()
    pathlib.Path(target_dir).mkdir(parents=True, exist_ok=True)
    Texture.set_texture_folder(directory)


class Test_Tile(unittest.TestCase):

    def test_building_basic_case(self):

        directory = "tests/city_tiler_test_data/junk/building_basic_case"
        cursor = open_data_base("tests/city_tiler_test_data/test_config.yml")
        objects_type = CityMBuildings
        create_directory(directory)
        objects_type.set_cursor(cursor)
        tileset = from_3dcitydb(cursor, objects_type)
        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
        tileset.write_to_directory(directory)
        cursor.close()

    def test_water_basic_case(self):

        directory = "tests/city_tiler_test_data/junk/water_basic_case"
        cursor = open_data_base("tests/city_tiler_test_data/test_config.yml")
        objects_type = CityMWaterBodies
        create_directory(directory)
        objects_type.set_cursor(cursor)
        tileset = from_3dcitydb(cursor, objects_type)
        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
        tileset.write_to_directory(directory)
        cursor.close()

    def test_relief_basic_case(self):

        directory = "tests/city_tiler_test_data/junk/relief_basic_case"
        cursor = open_data_base("tests/city_tiler_test_data/test_config.yml")
        objects_type = CityMReliefs
        create_directory(directory)
        objects_type.set_cursor(cursor)
        tileset = from_3dcitydb(cursor, objects_type)
        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
        tileset.write_to_directory(directory)
        cursor.close()

    def test_building_lod1(self):

        directory = "tests/city_tiler_test_data/junk/building_lod1"
        cursor = open_data_base("tests/city_tiler_test_data/test_config.yml")
        objects_type = CityMReliefs
        create_directory(directory)
        objects_type.set_cursor(cursor)
        tileset = from_3dcitydb(cursor, objects_type, create_lod1=True)
        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
        tileset.write_to_directory(directory)
        cursor.close()

    def test_building_loa(self):

        directory = "tests/city_tiler_test_data/junk/building_loa"
        cursor = open_data_base("tests/city_tiler_test_data/test_config.yml")
        objects_type = CityMBuildings
        create_directory(directory)
        objects_type.set_cursor(cursor)
        tileset = from_3dcitydb(cursor, objects_type, create_loa=True, polygons_path="tests/city_tiler_test_data/polygons")
        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
        tileset.write_to_directory(directory)
        cursor.close()

    def test_building_loa_lod1(self):

        directory = "tests/city_tiler_test_data/junk/building_loa_lod1"
        cursor = open_data_base("tests/city_tiler_test_data/test_config.yml")
        objects_type = CityMBuildings
        create_directory(directory)
        objects_type.set_cursor(cursor)
        tileset = from_3dcitydb(cursor, objects_type, create_lod1=True, create_loa=True, polygons_path="tests/city_tiler_test_data/polygons")
        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
        tileset.write_to_directory(directory)
        cursor.close()

    def test_building_BTH(self):

        directory = "tests/city_tiler_test_data/junk/building_BTH"
        cursor = open_data_base("tests/city_tiler_test_data/test_config.yml")
        objects_type = CityMBuildings
        CityMBuildings.set_bth()
        create_directory(directory)
        objects_type.set_cursor(cursor)
        tileset = from_3dcitydb(cursor, objects_type)
        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
        tileset.write_to_directory(directory)
        CityMBuildings.with_bth = False
        cursor.close()

    def test_building_split_surface(self):

        directory = "tests/city_tiler_test_data/junk/building_split_surface"
        cursor = open_data_base("tests/city_tiler_test_data/test_config.yml")
        objects_type = CityMBuildings
        create_directory(directory)
        objects_type.set_cursor(cursor)
        tileset = from_3dcitydb(cursor, objects_type, split_surfaces=True)
        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
        tileset.write_to_directory(directory)
        cursor.close()

    def test_relief_split_surface(self):

        directory = "tests/city_tiler_test_data/junk/relief_split_surface"
        cursor = open_data_base("tests/city_tiler_test_data/test_config.yml")
        objects_type = CityMReliefs
        create_directory(directory)
        objects_type.set_cursor(cursor)
        tileset = from_3dcitydb(cursor, objects_type, split_surfaces=True)
        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
        tileset.write_to_directory(directory)
        cursor.close()

    def test_water_split_surface(self):

        directory = "tests/city_tiler_test_data/junk/water_split_surface"
        cursor = open_data_base("tests/city_tiler_test_data/test_config.yml")
        objects_type = CityMWaterBodies
        create_directory(directory)
        objects_type.set_cursor(cursor)
        tileset = from_3dcitydb(cursor, objects_type, split_surfaces=True)
        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
        tileset.write_to_directory(directory)
        cursor.close()

    def test_building_texture(self):

        directory = "tests/city_tiler_test_data/junk/building_texture"
        cursor = open_data_base("tests/city_tiler_test_data/test_config.yml")
        objects_type = CityMBuildings
        create_directory(directory)
        objects_type.set_cursor(cursor)
        tileset = from_3dcitydb(cursor, objects_type, with_texture=True)
        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
        tileset.write_to_directory(directory)
        cursor.close()

    def test_relief_texture(self):

        directory = "tests/city_tiler_test_data/junk/relief_texture"
        cursor = open_data_base("tests/city_tiler_test_data/test_config.yml")
        objects_type = CityMReliefs
        create_directory(directory)
        objects_type.set_cursor(cursor)
        tileset = from_3dcitydb(cursor, objects_type, with_texture=True)
        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
        tileset.write_to_directory(directory)
        cursor.close()
