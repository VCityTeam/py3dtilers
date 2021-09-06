import unittest
import os
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