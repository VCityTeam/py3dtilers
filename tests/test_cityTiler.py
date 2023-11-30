import unittest
import pytest
from argparse import Namespace
from pathlib import Path
import psycopg2
import testing.postgresql

from py3dtilers.CityTiler.citym_cityobject import CityMCityObjects
from py3dtilers.CityTiler.citym_building import CityMBuildings
from py3dtilers.CityTiler.citym_relief import CityMReliefs
from py3dtilers.CityTiler.citym_waterbody import CityMWaterBodies
from py3dtilers.CityTiler.citym_bridge import CityMBridges
from py3dtilers.CityTiler.CityTiler import CityTiler


def get_default_namespace():
    return Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946',
                     crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, scale=1,
                     output_dir=None, geometric_error=[None, None, None],
                     split_surfaces=False, add_color=False, kd_tree_max=None, ids=[], texture_lods=0,
                     keep_ids=[], exclude_ids=[], no_normals=False, as_lods=False)


class Test_Tile(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        try:
            cls.postgresql = testing.postgresql.Postgresql()
            cls.db = psycopg2.connect(**cls.postgresql.dsn())
        except Exception:
            pytest.skip("Failed to setup test database")
        cls.cursor = cls.db.cursor()
        with open('tests/city_tiler_test_data/test_data.sql') as f:
            data = f.read()
            cls.cursor.execute("CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;")
            cls.cursor.execute("SELECT PostGIS_Lib_Version();")
            version = float(cls.cursor.fetchall()[0][0][0])
            if version >= 3:
                cls.cursor.execute("CREATE EXTENSION IF NOT EXISTS postgis_raster WITH SCHEMA public;")
            cls.cursor.execute(data)
            cls.cursor.execute("ALTER DATABASE " + cls.postgresql.dsn()['database'] + " SET search_path TO public, citydb;")
            CityMCityObjects.set_cursor(cls.cursor)

    @classmethod
    def tearDownClass(cls):
        cls.cursor.close()
        cls.db.close()
        cls.postgresql.stop()

    @classmethod
    def __del__(cls):
        print("Can't connect to the PostgreSQL database. Make sure PostgreSQL and PostGIS are installed locally.")

    def test_building_basic_case(self):

        objects_type = CityMBuildings
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/building_basic_case")
        tileset = city_tiler.from_3dcitydb(self.cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)

    def test_water_basic_case(self):

        objects_type = CityMWaterBodies
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/water_basic_case")
        tileset = city_tiler.from_3dcitydb(self.cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)

    def test_relief_basic_case(self):

        objects_type = CityMReliefs
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/relief_basic_case")
        tileset = city_tiler.from_3dcitydb(self.cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)

    def test_building_lod1(self):

        objects_type = CityMReliefs
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/building_lod1")
        city_tiler.args.lod1 = True
        tileset = city_tiler.from_3dcitydb(self.cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)

    def test_building_loa(self):

        objects_type = CityMBuildings
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/building_loa")
        city_tiler.args.loa = Path("tests/city_tiler_test_data/polygons")
        tileset = city_tiler.from_3dcitydb(self.cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)

    def test_building_loa_lod1(self):

        objects_type = CityMBuildings
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/building_loa_lod1")
        city_tiler.args.loa = Path("tests/city_tiler_test_data/polygons")
        city_tiler.args.lod1 = True
        tileset = city_tiler.from_3dcitydb(self.cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)

    def test_building_BTH(self):

        objects_type = CityMBuildings
        CityMBuildings.set_bth()
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/building_BTH")
        tileset = city_tiler.from_3dcitydb(self.cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)
        CityMBuildings.with_bth = False

    def test_building_split_surface(self):

        objects_type = CityMBuildings
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/building_split_surface")
        city_tiler.args.split_surfaces = True
        tileset = city_tiler.from_3dcitydb(self.cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)

    def test_relief_split_surface(self):

        objects_type = CityMReliefs
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/relief_split_surface")
        city_tiler.args.split_surfaces = True
        tileset = city_tiler.from_3dcitydb(self.cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)

    def test_water_split_surface(self):

        objects_type = CityMWaterBodies
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/water_split_surface")
        city_tiler.args.split_surfaces = True
        tileset = city_tiler.from_3dcitydb(self.cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)

    def test_building_texture(self):

        objects_type = CityMBuildings
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/building_texture")
        city_tiler.args.with_texture = True
        tileset = city_tiler.from_3dcitydb(self.cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)

    def test_building_texture_lods(self):

        objects_type = CityMBuildings
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/building_texture_lods")
        city_tiler.args.with_texture = True
        city_tiler.args.texture_lods = 5
        tileset = city_tiler.from_3dcitydb(self.cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)

    def test_relief_texture(self):

        objects_type = CityMReliefs
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/relief_texture")
        city_tiler.args.with_texture = True
        tileset = city_tiler.from_3dcitydb(self.cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)

    def test_bridge(self):

        objects_type = CityMBridges
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/bridge_basic_case")
        tileset = city_tiler.from_3dcitydb(self.cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)

    def test_bridge_split_surface(self):

        objects_type = CityMBridges
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/bridge_split_surface")
        city_tiler.args.split_surfaces = True
        tileset = city_tiler.from_3dcitydb(self.cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)

    def test_building_color(self):

        objects_type = CityMBuildings
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/building_color")
        city_tiler.args.add_color = True
        tileset = city_tiler.from_3dcitydb(self.cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)

    def test_building_keep_id(self):

        objects_type = CityMBuildings
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/building_keep_id")
        city_tiler.args.keep_ids = ["BU_69381AS107"]
        tileset = city_tiler.from_3dcitydb(self.cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)

    def test_relief_keep_id(self):

        objects_type = CityMReliefs
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/relief_keep_id")
        city_tiler.args.keep_ids = ["TIN_8184c814-97b6-4d26-a6f2-03ef4bd6e65d"]
        tileset = city_tiler.from_3dcitydb(self.cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)

    def test_waterbody_keep_id(self):

        objects_type = CityMWaterBodies
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/waterbody_keep_id")
        city_tiler.args.keep_ids = ["a47bd1e2-f63a-450f-b0d4-4ce25798966d"]
        tileset = city_tiler.from_3dcitydb(self.cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)

    def test_bridge_keep_id(self):

        objects_type = CityMBridges
        city_tiler = CityTiler()
        city_tiler.args = get_default_namespace()
        city_tiler.args.output_dir = Path("tests/city_tiler_test_data/generated_tilesets/bridge_keep_id")
        city_tiler.args.keep_ids = ["ID_58ee6b1f-48eb-4907-9c7a-679354adc73f"]
        tileset = city_tiler.from_3dcitydb(self.cursor, objects_type)

        tileset.write_as_json(city_tiler.args.output_dir)


if __name__ == '__main__':
    unittest.main()
