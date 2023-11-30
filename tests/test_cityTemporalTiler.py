import unittest
from argparse import Namespace
from pathlib import Path
import psycopg2
import testing.postgresql

from py3dtiles import TemporalBoundingVolume

from py3dtilers.CityTiler.temporal_graph import TemporalGraph
from py3dtilers.CityTiler.CityTemporalTiler import CityTemporalTiler


class Args():
    def __init__(self):
        self.temporal_graph = [Path("tests/city_temporal_tiler_test_data/graph_2009-2012.json")]
        self.db_config_path = []
        self.time_stamps = ["2009", "2012"]


def get_default_namespace():
    return Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946',
                     crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, scale=1,
                     output_dir=None, geometric_error=[None, None, None],
                     split_surfaces=False, add_color=False, kd_tree_max=None, texture_lods=0,
                     keep_ids=[], exclude_ids=[], no_normals=False, as_lods=False)


class Test_Tile(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        try:
            cls.postgresql_2009 = testing.postgresql.Postgresql()
            cls.db_2009 = psycopg2.connect(**cls.postgresql_2009.dsn())
        except Exception:
            raise
        cls.cursor_2009 = cls.db_2009.cursor()
        with open('tests/city_temporal_tiler_test_data/test_data_temporal_2009.sql') as f:
            data = f.read()
            cls.cursor_2009.execute("CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;")
            cls.cursor_2009.execute("SELECT PostGIS_Lib_Version();")
            version = float(cls.cursor_2009.fetchall()[0][0][0])
            if version >= 3:
                cls.cursor_2009.execute("CREATE EXTENSION IF NOT EXISTS postgis_raster WITH SCHEMA public;")
            cls.cursor_2009.execute(data)
            cls.cursor_2009.execute("ALTER DATABASE " + cls.postgresql_2009.dsn()['database'] + " SET search_path TO public, citydb;")

        try:
            cls.postgresql_2012 = testing.postgresql.Postgresql()
            cls.db_2012 = psycopg2.connect(**cls.postgresql_2012.dsn())
        except Exception:
            raise
        cls.cursor_2012 = cls.db_2012.cursor()
        with open('tests/city_temporal_tiler_test_data/test_data_temporal_2012.sql') as f:
            data = f.read()
            cls.cursor_2012.execute("CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;")
            cls.cursor_2012.execute("SELECT PostGIS_Lib_Version();")
            version = float(cls.cursor_2012.fetchall()[0][0][0])
            if version >= 3:
                cls.cursor_2012.execute("CREATE EXTENSION IF NOT EXISTS postgis_raster WITH SCHEMA public;")
            cls.cursor_2012.execute(data)
            cls.cursor_2012.execute("ALTER DATABASE " + cls.postgresql_2012.dsn()['database'] + " SET search_path TO public, citydb;")

    @classmethod
    def tearDownClass(cls):
        cls.cursor_2009.close()
        cls.db_2009.close()
        cls.postgresql_2009.stop()
        cls.cursor_2012.close()
        cls.db_2012.close()
        cls.postgresql_2012.stop()

    @classmethod
    def __del__(cls):
        print("Can't connect to the PostgreSQL database. Make sure PostgreSQL and PostGIS are installed locally.")

    def test_temporal(self):
        city_temp_tiler = CityTemporalTiler()
        city_temp_tiler.args = get_default_namespace()
        city_temp_tiler.args.output_dir = Path("tests/city_temporal_tiler_test_data/generated_tilesets/temporal")
        cli_args = Args()
        graph = TemporalGraph(cli_args)
        graph.reconstruct_connectivity()

        graph.display_characteristics('   ')
        graph.simplify(display_characteristics=True)

        cursors = [self.cursor_2009, self.cursor_2012]
        time_stamped_cursors = dict()
        for index in range(len(cursors)):
            time_stamped_cursors[cli_args.time_stamps[index]] = cursors[index]
        all_buildings = city_temp_tiler.combine_nodes_with_buildings_from_3dcitydb(
            graph,
            cursors,
            cli_args)

        tile_set = city_temp_tiler.from_3dcitydb(time_stamped_cursors, all_buildings)

        tile_set.get_root_tile().get_bounding_volume().add_extension(TemporalBoundingVolume())

        temporal_tile_set = city_temp_tiler.build_temporal_tile_set(graph)
        tile_set.add_extension(temporal_tile_set)

        tile_set.write_as_json(city_temp_tiler.args.output_dir)


if __name__ == '__main__':
    unittest.main()
