import unittest
from argparse import Namespace
from pathlib import Path

from py3dtiles import TemporalBoundingVolume

from py3dtilers.CityTiler.temporal_graph import TemporalGraph
from py3dtilers.CityTiler.database_accesses import open_data_bases
from py3dtilers.CityTiler.CityTemporalTiler import CityTemporalTiler


class Args():
    def __init__(self):
        self.temporal_graph = [Path("tests/city_temporal_tiler_test_data/graph_2009-2012.json")]
        self.db_config_path = [Path("tests/city_temporal_tiler_test_data/test_config_2009.yml"),
                               Path("tests/city_temporal_tiler_test_data/test_config_2012.yml")]
        self.time_stamps = ["2009", "2012"]


class Test_Tile(unittest.TestCase):

    def test_temporal(self):
        city_temp_tiler = CityTemporalTiler()
        output_dir = Path("tests/city_temporal_tiler_test_data/generated_tilesets/temporal")
        city_temp_tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=output_dir, split_surfaces=False)
        cli_args = Args()
        graph = TemporalGraph(cli_args)
        graph.reconstruct_connectivity()

        graph.display_characteristics('   ')
        graph.simplify(display_characteristics=True)

        cursors = open_data_bases(cli_args.db_config_path)
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

        [cursor.close() for cursor in cursors]

        tile_set.write_to_directory(output_dir)


if __name__ == '__main__':
    unittest.main()
