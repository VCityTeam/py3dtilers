import sys

from py3dtiles import TemporalBoundingVolume
from py3dtiles import TemporalTileSet
from py3dtiles import TemporalTransaction
from py3dtiles import TemporalPrimaryTransaction, TemporalTransactionAggregate
from py3dtiles import TriangleSoup

from .temporal_utils import debug_msg
from .temporal_graph import TemporalGraph, Edge
from .temporal_building import TemporalBuilding

from .citym_cityobject import CityMCityObjects
from .citym_building import CityMBuildings
from .CityTiler import CityTiler

from .database_accesses import open_data_bases


class CityTemporalTiler(CityTiler):

    def __init__(self):
        super().__init__()

        self.parser.add_argument('--time_stamps',
                                 nargs='+',
                                 type=str,
                                 help='Time stamps (corresponding to each database)')
        self.parser.add_argument('--temporal_graph',
                                 nargs='+',
                                 type=str,
                                 help='GraphML-Json temporal data filename(s)')

    def parse_command_line(self):
        super().parse_command_line()

        if len(self.args.paths) <= 1:
            print("Only a single database configuration file was provided.")
            print("This is highly suspect since temporal comparisons require at")
            print("least two time-stamps and thus two databases (one for each).")
            print("Exiting.")
            sys.exit(1)
        else:
            # When there is more than one database there should be as
            # as many time stamps as databases (because each time stamp
            # corresponds to a database:
            if not self.args.time_stamps:
                # How come the nargs+ doesn't deal with this case ?
                print("There must be as many time-stamps as databases.")
                print("Provide time-stamps with the --time_stamps option.")
                sys.exit(1)
            if len(self.args.paths) != len(self.args.time_stamps):
                print("Mismatching number of databases vs time-stamps:")
                print(" - databases (configurations): ", self.args.paths)
                print(" - timestamps: ", self.args.time_stamps)
                print("Exiting.")
                sys.exit(1)

    def get_surfaces_merged(self, cursors, cityobjects, objects_type):
        """
        Get the surfaces of all the cityobjects and transform them into TriangleSoup
        Surfaces of the same cityObject are merged into one geometry
        """
        cityobjects_with_geom = list()
        for cityobject in cityobjects:
            try:
                id = '(' + str(cityobject.get_database_id()) + ')'
                time_stamp = cityobject.get_time_stamp()
                cursors[time_stamp].execute(objects_type.sql_query_geometries(id, False))
                for t in cursors[time_stamp].fetchall():
                    geom_as_string = t[1]
                    cityobject.geom = TriangleSoup.from_wkb_multipolygon(geom_as_string)
                    cityobject.set_box()
                    cityobjects_with_geom.append(cityobject)
            except AttributeError:
                continue
        return objects_type(cityobjects_with_geom)

    def from_3dcitydb(self, cursors, buildings):
        """
        :param cursors: a dictionary with a timestamp as key and database cursors
                        as values
        :param buildings: a Buildings object
        """

        if not buildings:
            raise ValueError(f'The database does not contain any {CityMBuildings} object')

        feature_list = self.get_surfaces_merged(cursors, buildings, CityMBuildings)

        return self.create_tileset_from_feature_list(feature_list, extension_name="temporal")

    def combine_nodes_with_buildings_from_3dcitydb(self, graph, cursors, cli_args):
        # ######## Convert the nodes to buildings (optimization purpose)
        # Constructing the pre-tiling stage (i.e. sorting out the cityGML objects
        # in a 2D-Tree used as input to the TileSet construction per-se, refer to
        # to the from_3dcitydb() method) requires the objects bounding boxes. Once
        # retrieved we would have to match the retrieved building with the upcoming
        # nodes in order to transfer the temporal information (creation/deletion
        # dates). In order to avoid this possibly expensive matching, we create
        # temporal buildings and let from_3dcitydb() decorate those objects with
        # the information it extracts from the database:
        resulting_buildings = CityMBuildings()
        for index, time_stamp in enumerate(cli_args.time_stamps):
            cursor = cursors[index]
            nodes = graph.get_nodes_with_time_stamp(time_stamp)
            buildings = CityMBuildings()
            for node in nodes:
                new_building = TemporalBuilding()
                new_building.set_start_date(node.get_start_date())
                new_building.set_end_date(node.get_end_date())
                new_building.set_temporal_id(node.get_global_id())
                new_building.set_gml_id(node.get_local_id())
                buildings.append(new_building)
            if not buildings:
                continue
            extracted_buildings = CityMCityObjects.retrieve_objects(
                cursor, CityMBuildings, buildings)
            resulting_buildings.extend(extracted_buildings)
        return resulting_buildings

    def build_temporal_tile_set(self, graph):
        # ####### We are left with transposing the information carried by the
        # graph edges to transactions
        debug_msg('  Creating transactions')
        temporal_tile_set = TemporalTileSet()
        for edge in graph.edges:
            if not edge.is_modified():
                continue
            if not edge.are_adjacent_nodes_one_to_one():
                continue
            ancestor = edge.get_ancestor()
            descendant = edge.get_descendant()
            transaction = TemporalPrimaryTransaction()
            transaction.set_start_date(ancestor.get_end_date())
            transaction.set_end_date(descendant.get_start_date())
            transaction.set_type('modification')
            transaction.append_source(ancestor.get_global_id())
            transaction.append_destination(descendant.get_global_id())
            temporal_tile_set.append_transaction(transaction)

        # ######## Re-qualifying modified-fusion or modified-subdivision
        # When they are many modified edges adjacent to a single node
        # then this indicates that such edges were incompletely labeled
        # since they miss the tags 'subdivision' or 'fused' in addition
        # to the modified one. In other terms we encountered a combination
        # of subdivision (or fusion) with a modification.
        # In such a case we re-qualify those edges and let the next stage
        # (fused and subdivision edge transactions) treat them:
        time_stamps = graph.extract_time_stamps()
        for time_stamp in time_stamps:
            current_nodes = graph.get_nodes_with_time_stamp(time_stamp)
            for node in current_nodes:
                if not node.are_all_ancestor_edges_of_type(Edge.Tag.modified):
                    continue
                for ancestor_edge in node.get_ancestor_edges():
                    ancestor_edge.append_tag(Edge.Tag.fused)

        for time_stamp in time_stamps:
            current_nodes = graph.get_nodes_with_time_stamp(time_stamp)
            for node in current_nodes:
                if not node.are_all_descendant_edges_of_type(Edge.Tag.modified):
                    continue
                for descendant_edge in node.get_descendant_edges():
                    descendant_edge.append_tag(Edge.Tag.subdivided)

        # ####### The union case
        for time_stamp in time_stamps:
            current_nodes = graph.get_nodes_with_time_stamp(time_stamp)
            for node in current_nodes:
                if not node.are_all_ancestor_edges_of_type(Edge.Tag.fused):
                    continue

                # At first we do _not_ know whether the resulting transaction will
                # be a
                #  - a simple PrimaryTransaction of union type
                #  - or an TransactionAggregate nesting the above (simple case) of
                #    fusion PrimaryTransaction together with another simple
                #    PrimaryTransaction of modification type
                # Note that when both PrimaryTransactions happen to exist we need
                # the three created transactions (the two primary transactions
                # with the transaction aggregate holding them) to share the same
                # (redundant) information (that is the attributes of the base
                # class that they share i.e. a TemporalTransaction).
                # We thus make a first pass where on the one hand we collect the
                # elements of the transaction(s) and on the other hand on the other
                # decide which case we are facing.
                aggregate_required = False
                transaction_elements = TemporalTransaction()
                transaction_elements.append_destination(node.get_global_id())

                if not node.do_all_ancestor_nodes_share_same_date():
                    debug_msg("Warning: union transaction surely erroneous...")
                # We here make the assumption that all ancestor nodes are all
                # sharing the same deletion date for the following code to make
                # sense:
                some_ancestor = node.get_ancestors()[0]
                transaction_elements.set_start_date(some_ancestor.get_end_date())
                transaction_elements.set_end_date(node.get_start_date())

                for ancestor in node.get_ancestors():
                    transaction_elements.append_source(ancestor.get_global_id())
                for ancestor_edge in node.get_ancestor_edges():
                    if ancestor_edge.is_modified():
                        aggregate_required = True
                        break

                # We can now wrap the collected elements into the ad-hoc
                # transaction:
                union_transaction = TemporalPrimaryTransaction()
                union_transaction.replicate_from(transaction_elements)
                union_transaction.set_type('union')

                if not aggregate_required:
                    resulting_transaction = union_transaction
                else:
                    resulting_transaction = TemporalTransactionAggregate()
                    resulting_transaction.replicate_from(transaction_elements)
                    resulting_transaction.append_transaction(union_transaction)
                    modification_transaction = TemporalPrimaryTransaction()
                    modification_transaction.replicate_from(transaction_elements)
                    modification_transaction.set_type('modification')
                    resulting_transaction.append_transaction(
                        modification_transaction)
                # And eventually attach the result to the the tile set
                temporal_tile_set.append_transaction(resulting_transaction)

        # ####### The subdivision case
        for time_stamp in time_stamps:
            current_nodes = graph.get_nodes_with_time_stamp(time_stamp)
            for node in current_nodes:
                if not node.are_all_descendant_edges_of_type(Edge.Tag.subdivided):
                    continue

                # Refer to the above fusion case for comments concerning the
                # algorithm logic used for creating the transaction(s):
                aggregate_required = False
                transaction_elements = TemporalTransaction()
                transaction_elements.append_source(node.get_global_id())

                if not node.do_all_descendant_nodes_share_same_date():
                    debug_msg("Warning: erroneous subdivision transaction ?")
                # We here make the assumption that all descendant nodes all share
                # the same deletion date for the following code to make sense:
                some_descendant = node.get_descendants()[0]
                transaction_elements.set_end_date(some_descendant.get_start_date())
                transaction_elements.set_start_date(node.get_end_date())

                for descendant in node.get_descendants():
                    transaction_elements.append_destination(
                        descendant.get_global_id())

                for descendant_edge in node.get_descendant_edges():
                    if descendant_edge.is_modified():
                        aggregate_required = True
                        break

                # We can now wrap the collected elements into the ad-hoc
                # transaction:
                union_transaction = TemporalPrimaryTransaction()
                union_transaction.replicate_from(transaction_elements)
                union_transaction.set_type('division')

                if not aggregate_required:
                    resulting_transaction = union_transaction
                else:
                    resulting_transaction = TemporalTransactionAggregate()
                    resulting_transaction.replicate_from(transaction_elements)
                    resulting_transaction.append_transaction(union_transaction)
                    modification_transaction = TemporalPrimaryTransaction()
                    modification_transaction.replicate_from(transaction_elements)
                    modification_transaction.set_type('modification')
                    resulting_transaction.append_transaction(
                        modification_transaction)
                # And eventually attach the result to the the tile set
                temporal_tile_set.append_transaction(resulting_transaction)

        return temporal_tile_set


def main():
    city_temp_tiler = CityTemporalTiler()
    city_temp_tiler.parse_command_line()
    cli_args = city_temp_tiler.args

    # #### Reconstruct the graph
    graph = TemporalGraph(cli_args)
    graph.reconstruct_connectivity()
    debug_msg("Reconstructed graph characteristics:")
    # graph.print_nodes_and_edges()
    graph.display_characteristics('   ')
    graph.simplify(display_characteristics=True)
    debug_msg("")
    # graph.print_nodes_and_edges()

    # Just making sure the time stamps information is coherent between
    # their two sources that is the set of difference files and the command
    # line arguments
    cli_time_stamps_as_ints = [int(ts) for ts in cli_args.time_stamps]
    for extracted_time_stamp in graph.extract_time_stamps():
        if extracted_time_stamp not in cli_time_stamps_as_ints:
            print('Command line and difference files time stamps not aligned.')
            print("Exiting")
            sys.exit(1)

    # Extract the information form the databases
    cursors = open_data_bases(cli_args.paths)
    time_stamped_cursors = dict()
    for index in range(len(cursors)):
        time_stamped_cursors[cli_args.time_stamps[index]] = cursors[index]
    all_buildings = city_temp_tiler.combine_nodes_with_buildings_from_3dcitydb(
        graph,
        cursors,
        cli_args)

    # Construct the temporal tile set
    tile_set = city_temp_tiler.from_3dcitydb(time_stamped_cursors, all_buildings)

    tile_set.get_root_tile().get_bounding_volume().add_extension(TemporalBoundingVolume())

    # Build and attach a TemporalTileSet extension
    temporal_tile_set = city_temp_tiler.build_temporal_tile_set(graph)
    tile_set.add_extension(temporal_tile_set)

    # A shallow attempt at providing some traceability on where the resulting
    # data set comes from:
    origin = f'This tileset is the result of Py3DTiles {__file__} script '
    origin += 'ran with data extracted from the following databases:'
    for cursor in cursors:
        cursor.execute('SELECT inet_client_addr()')
        server_ip = cursor.fetchone()[0]
        cursor.execute('SELECT current_database()')
        database_name = cursor.fetchone()[0]
        origin += '   - ' + server_ip + ': ' + database_name + '\n'

    tile_set.add_asset_extras(origin)

    [cursor.close() for cursor in cursors]  # We are done with the databases

    tile_set.write_as_json(city_temp_tiler.get_output_dir())


if __name__ == '__main__':
    main()
