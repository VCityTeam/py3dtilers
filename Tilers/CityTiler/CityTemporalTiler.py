import argparse
import numpy as np
import json
import sys
from enum import Enum, unique

from pprint import pprint

from py3dtiles import B3dm, BatchTable, BoundingVolumeBox, GlTF
from py3dtiles import Tile, TileSet

from building import Building, Buildings
from kd_tree import kd_tree
from database_accesses import open_data_base, retrieve_geometries, \
    create_batch_table_hierachy


def ParseCommandLine():
    # arg parse
    descr = '''A small utility that build a 3DTiles tileset out of 
               - temporal data of the buildings
               - the content of a 3DCityDB database.'''
    parser = argparse.ArgumentParser(description=descr)
    parser.add_argument('--db_config_path',
                        nargs='?',
                        default='CityTilerDBConfig.yml',
                        type=str,

                        help='Path to the database configuration file')
    parser.add_argument('--temporal_graph',
                        nargs='+',
                        type=str,
                        help='GraphML-Json temporal data filename(s)')
    parser.add_argument('--with_BTH',
                        dest='with_BTH',
                        action='store_true',
                        help='Adds a Batch Table Hierachy when defined')
    return parser.parse_args()


def create_tile_content(cursor, buildingIds, offset, args):
    """
    :param offset: the offset (a a 3D "vector" of floats) by which the
                   geographical coordinates should be translated (the
                   computation is done at the GIS level)
    :type args: CLI arguments as obtained with an ArgumentParser. Used to
                determine whether to define attach an optional
                BatchTable or possibly a BatchTableHierachy
    :rtype: a TileContent in the form a B3dm.
    """
    arrays = retrieve_geometries(cursor, buildingIds, offset)

    # GlTF uses a y-up coordinate system whereas the geographical data (stored
    # in the 3DCityDB database) uses a z-up coordinate system convention. In
    # order to comply with Gltf we thus need to realize a z-up to y-up
    # coordinate transform for the data to respect the glTF convention. This
    # rotation gets "corrected" (taken care of) by the B3dm/gltf parser on the
    # client side when using (displaying) the data.
    # Refer to the note concerning the recommended data workflow
    #    https://github.com/AnalyticalGraphicsInc/3d-tiles/tree/master/specification#gltf-transforms
    # for more details on this matter.
    transform = np.array([1, 0, 0, 0,
                          0, 0, -1, 0,
                          0, 1, 0, 0,
                          0, 0, 0, 1])
    gltf = GlTF.from_binary_arrays(arrays, transform)

    # When required attach a BatchTable with its optional extensions
    if args.with_BTH:
        bth = create_batch_table_hierachy(cursor, buildingIds, args)
        bt = BatchTable()
        bt.add_extension(bth)
    else:
        bt = None

    # Eventually wrap the geometries together with the optional
    # BatchTableHierarchy within a B3dm:
    return B3dm.from_glTF(gltf, bt)


def from_3dcitydb(cursor, args):
    """
    :type args: CLI arguments as obtained with an ArgumentParser.
    """

    # Retrieve all the buildings encountered in the 3DCityDB database together
    # with their 3D bounding box.
    cursor.execute("SELECT building.id, BOX3D(cityobject.envelope) "
                   "FROM building JOIN cityobject ON building.id=cityobject.id "
                   "WHERE building.id=building.building_root_id")
    buildings = Buildings()
    for t in cursor.fetchall():
        id = t[0]
        if not t[1]:
            print("Warning: droping building with id ", id)
            print("         because its 'cityobject.envelope' is not defined.")
            continue
        box = t[1]
        buildings.append(Building(id, box))

    # Lump out buildings in pre_tiles based on a 2D-Tree technique:
    pre_tiles = kd_tree(buildings, 20)

    tileset = TileSet()
    for tile_buildings in pre_tiles:
        tile = Tile()
        tile.set_geometric_error(500)

        # Construct the tile content and attach it to the new Tile:
        ids = tuple([building.getId() for building in tile_buildings])
        centroid = tile_buildings.getCentroid()
        tile_content_b3dm = create_tile_content(cursor, ids, centroid, args)
        tile.set_content(tile_content_b3dm)

        # The current new tile bounding volume shall be a box enclosing the
        # buildings withheld in the considered tile_buildings:
        bounding_box = BoundingVolumeBox()
        for building in tile_buildings:
            bounding_box.add(building.getBoundingVolumeBox())

        # The Tile Content returned by the above call to create_tile_content()
        # (refer to the usage of the centroid/offset third argument) uses
        # coordinates that are local to the centroid (considered as a
        # referential system within the chosen geographical coordinate system).
        # Yet the above computed bounding_box was set up based on
        # coordinates that are relative to the chosen geographical coordinate
        # system. We thus need to align the Tile Content to the
        # BoundingVolumeBox of the Tile by "adjusting" to this change of
        # referential:
        bounding_box.translate([- centroid[i] for i in range(0, 3)])
        tile.set_bounding_volume(bounding_box)

        # The transformation matrix for the tile is limited to a translation
        # to the centroid (refer to the offset realized by the
        # create_tile_content() method).
        # Note: the geographical data (stored in the 3DCityDB) uses a z-up
        #       referential convention. When building the B3dm/gltf, and in
        #       order to comply to the y-up gltf convention) it was necessary
        #       (look for the definition of the `transform` matrix when invoking
        #       `GlTF.from_binary_arrays(arrays, transform)` in the
        #        create_tile_content() method) to realize a z-up to y-up
        #        coordinate transform. The Tile is not aware on this z-to-y
        #        rotation (when writing the data) followed by the invert y-to-z
        #        rotation (when reading the data) that only concerns the gltf
        #        part of the TileContent.
        tile.set_transform([1, 0, 0, 0,
                            0, 1, 0, 0,
                            0, 0, 1, 0,
                            centroid[0], centroid[1], centroid[2], 1])

        # Eventually we can add the newly build tile to the tile set:
        tileset.add_tile(tile)

    # Note: we don't need to explicitly adapt the TileSet's root tile
    # bounding volume, because TileSet::write_to_directory() already
    # takes care of this synchronisation.

    # A shallow attempt at providing some traceability on where the resulting
    # data set comes from:
    cursor.execute('SELECT inet_client_addr()')
    server_ip = cursor.fetchone()[0]
    cursor.execute('SELECT current_database()')
    database_name = cursor.fetchone()[0]
    origin = f'This tileset is the result of Py3DTiles {__file__} script '
    origin += f'run with data extracted from database {database_name} '
    origin += f' obtained from server {server_ip}.'
    tileset.add_asset_extras(origin)

    return tileset


class Node(object):
    @unique
    class Status(Enum):
        """
        Historical status of the node (mainly used on documentation/debug
        purposes) indicating the nature of the node in its relationship
        with past and future nodes
        """
        unknown = 1
        # Appears isolated at a single time stamp (neither ancestors nor
        # descendants)
        hapax = 2
        # Beginning of a lineage of nodes (no ancestors)
        start = 3
        # Termination of a lineage of nodes (no descendants)
        end = 4
        # Historical link/connection between the past nodes and future nodes
        # (has both ancestors and descendants)
        link = 5

    def __init__(self, **kwargs):
        # Attributes that will be dynamically added by the Json parsing
        # self.id : an integer used as Node identifier (local to a single
        #           Graph file)
        # self.globalid: an string (global) identifier used as Node identifier
        #                valid across a set of Graph files
        self.__dict__ = kwargs

        self.creation_date = None
        self.deletion_date = None
        # The list of nodes which are the source of an edge that this
        # adjacent with this node (this node being the target of that edge).
        # As such, those nodes come before in time and thus ancestors:
        self.ancestors = list()
        # The list of nodes which are the target of an edge that this
        # adjacent with this node (this node being the source of that edge).
        # As such, those nodes come after in time and thus descendants:
        self.descendants = list()
        self.status = Node.Status.unknown

    def is_unknown(self):
        if self.status == Node.Status.unknown:
            return True
        return False

    def is_hapax(self):
        if self.status == Node.Status.hapax:
            return True
        return False

    def is_start(self):
        if self.status == Node.Status.start:
            return True
        return False

    def is_end(self):
        if self.status == Node.Status.end:
            return True
        return False

    def is_link(self):
        if self.status == Node.Status.link:
            return True
        return False

    def assert_status_coherence(self):
        if not self.ancestors and not self.descendants:
            if self.is_unknown():
                # No information and nothing to assert
                return
            if self.is_hapax():
                # A hapax indeed has not ancestors nor descendants
                return
            else:
                print("Only a hapax has neither ancestors nor descendants.")
                sys.exit(1)
        if self.ancestors and not self.descendants:
            if self.is_unknown():
                print("Should have been an end prior to having ancestors.")
                sys.exit(1)
            return
        if not self.ancestors and self.descendants:
            if self.is_unknown():
                print("Should have been a start prior to having descendants.")
                sys.exit(1)
            return
        # The Node has both ancestors and descendants:
        if self.is_unknown():
            print("Should have been a hapax, a start or end prior to having")
            print("both ancestors and descendants.")
            sys.exit(1)
        if not self.is_link():
            print("This node has both ancestors and descendants but is not")
            print("a link but a: ", self.status)
            sys.exit(1)

    def get_time_stamp(self):
        return int(self.globalid.split('::')[0])

    def set_creation_date_if_earlier(self, time_stamp):
        """
        When the given time_stamp is earlier than the current value of
        the node creation_date then set the creation_date with that value
        :param node: the concerned node
        :param time_stamp: the time stamp that should be set when it is earlier
        :return: None
        """
        if not self.creation_date:
            self.creation_date = time_stamp
            return
        if time_stamp < self.creation_date:
            self.creation_date = time_stamp

    def set_creation_date_recursive(self, time_stamp):
        self.set_creation_date_if_earlier(time_stamp)
        for descendant in self.descendants:
            descendant.set_creation_date_recursive(time_stamp)

    def set_deletion_date_if_later(self, time_stamp):
        if not self.deletion_date:
            self.deletion_date = time_stamp
            return
        if time_stamp > self.deletion_date:
            self.deletion_date = time_stamp

    def get_ancestors(self):
        return self.ancestors

    def add_ancestors(self, ancestor_list):
        self.ancestors += ancestor_list

    def get_direct_descendants(self):
        return self.descendants

    def add_descendants(self, descendant_list):
        self.descendants += descendant_list

    def set_hapax(self, time_stamp):
        if not self.is_unknown():
            print("Failing to promote as hapax from status: ", self.status)
            sys.exit(1)
        self.status = Node.Status.hapax
        if self.creation_date:
            print("This newly converted hapax already had a creation_date.")
            sys.exit(1)
        self.creation_date = time_stamp
        if self.deletion_date:
            print("This newly converted hapax already had a deletion_date.")
            sys.exit(1)
        self.deletion_date = time_stamp
        self.assert_status_coherence()

    def set_start(self, time_stamp = None):
        if self.is_hapax():
            print("Failed to convert a hapax into being a start.")
            sys.exit(1)
        if self.is_end():
            print("Failed to convert an end into being a start.")
            sys.exit(1)
        if self.is_link():
            print("Failed to convert a link into being a start.")
            sys.exit(1)
        self.status = Node.Status.start
        if self.creation_date:
            print("This newly converted start already had a creation_date.")
            sys.exit(1)
        if time_stamp:
            self.creation_date = time_stamp
        self.assert_status_coherence()

    def set_end(self, time_stamp):
        if self.is_hapax():
            print("Failed to convert a hapax to being an end.")
            sys.exit(1)
        if not self.is_unknown():
            print("Failed to define as end.")
            sys.exit(1)
        self.status = Node.Status.end
        if self.deletion_date:
            print("This newly converted end already had a deletion_date.")
            sys.exit(1)
        self.deletion_date = time_stamp
        self.assert_status_coherence()

    def set_link(self):
        if self.is_unknown():
            print("An unknown node should not be converted to being an link.")
            sys.exit(1)
        if self.is_hapax():
            print("An hapax node should not be converted to being an link.")
            sys.exit(1)
        self.status = Node.Status.link


class Edge(object):
    def __init__(self, **kwargs):
        # Attributes that will be dynamically added by the Json parsing
        # self.id : an integer used as Node identifier (local to a single
        #           Graph file)
        # self.source: an integer designating a source Node
        # self.target: an integer designating a target Node
        # self.comment: a string documenting the transition from source to
        #               target
        self.__dict__ = kwargs

class Graph(object):
    def __init__(self, nodes=None, edges=None):
        if not nodes:
            self.nodes = list()
        else:
            self.nodes = nodes
        if not edges:
            self.edges = list()
        else:
            self.edges = edges

    def extend_with_subgraph(self, sub_graph):
        self.nodes += sub_graph.nodes
        self.edges += sub_graph.edges

    def get_ancestors(self, node):
        """
        Retrieve the ancestor (nodes) of the considered node i.e. the nodes
        that are the source of the edges that have the considered node as
        target
        :param node: the node of which we are looking the ancestors for
        :return: a list of ancestor nodes (without duplicates
        """
        # There can be multiple edges between a given source node and a given
        # destination node:
        multiple_ancestors = [e.source for e in self.edges
                              if e.target.globalid == node.globalid]
        # Simplify the list by removing duplicates
        ancestors = list(set(multiple_ancestors))
        return ancestors

    def reconstruct_ancestors_graph(self, time_stamp):
        latest_nodes = [n for n in self.nodes
                        if n.get_time_stamp() == time_stamp]
        for n in latest_nodes:
            # The inquiry towards past and future is asymmetrical because we
            # swipe from future to past
            ancestors = self.get_ancestors(n)
            descendants = n.get_direct_descendants()
            if not ancestors and not descendants:
                # This node had no future and no past was found. It is thus
                # isolated in history:
                n.set_hapax(time_stamp)
                continue
            if ancestors:
                # We found ancestors: inform them of this new descendant
                for ancestor in ancestors:
                    ancestor.add_descendants([n])
                    ancestor.set_deletion_date_if_later(time_stamp)
                    ancestor.set_start()
                    ancestor.assert_status_coherence()
                n.add_ancestors(ancestors)
            if descendants:
                for descendant in descendants:
                    # The descendants should already know about the existence of
                    # the present node as being their ancestor (since this
                    # information should have been discovered at the previous
                    # round i.e. when those descendants where looking for their
                    # own ancestor). Assert this is the case:
                    if n not in descendant.get_ancestors():
                        print("Some descendants don't know their ancestor!?")
                        sys.exit(1)
                    # We are thus left with informing them of the time_stamp
                    descendant.set_creation_date_recursive(time_stamp)
                    descendant.assert_status_coherence()
            if ancestors and not descendants:
                n.set_end(time_stamp)
                continue
            if not ancestors and descendants:
                n.set_start(time_stamp)
                continue
            # We are left with the case
            #   len(ancestors) != 0 and len(descendants) != 0
            n.set_link()

class GraphMLDecoder(json.JSONDecoder):
    def __init__(self):
        json.JSONDecoder.__init__(self, object_hook=self.dict_to_object)

    def dict_to_object(self, dct):
        if 'id' in dct and 'globalid' in dct:
            return Node(**dct)
        if 'id' in dct and 'source' in dct and 'target' in dct and 'comment' in dct:
            return Edge(**dct)
        return dct


def process_temporal_data(args):
    graph = Graph()
    # Deserialize the temporal (sub) graphs to constitute the general graph
    for temporal_graph_filename in args.temporal_graph:
        with open(temporal_graph_filename, 'r') as temporal_graph_file:
            temporal_graph = json.loads(temporal_graph_file.read(),
                                        cls=GraphMLDecoder)
        current_nodes = temporal_graph['nodes']
        # Because the Json GraphML we parse is produced with boost::ptree's
        # write_json method that is well known for not conforming to Json
        # (integers are serialized as strings i.e. enclosed with double quotes)
        # we need to "fix" things after the Json parser is run
        for node in current_nodes:
            if isinstance(node.id, str):
                node.id = int(node.id)

        current_edges = temporal_graph['edges']
        # Edges id must also be type fixed (refer above to current_nodes)
        for edge in current_edges:
            if isinstance(edge.id, str):
                edge.id = int(edge.id)

        # Additionally we need to replace the node indexes (integer) loaded
        # as source and target (with the Json type fix) to their corresponding
        # references (as python objects):
        for edge in current_edges:
            if isinstance(edge.source, str):
                edge.source = current_nodes[int(edge.source)]
            if isinstance(edge.target, str):
                edge.target = current_nodes[int(edge.target)]
        # Eventually we can poor the current graph with the other graphs
        graph.extend_with_subgraph(Graph(current_nodes, current_edges))

    # Retrieve, out of the node's global identifier, an ordered (from oldest
    # to most recent) list of time stamps (where the oldest time stamp is
    # weeded out):
    time_stamps_set = set()
    for node in graph.nodes:
        time_stamps_set.add(node.get_time_stamp())
    time_stamps = list(time_stamps_set)
    time_stamps.sort()

    # We iterate on the time stamps (minus the oldest) in order to
    # reconstruct the objects (building) historical (highly non connected)
    # graph. We start from the most recent time stamp and proceed towards
    # the past. Note that the oldest time stamp is removed because the graph
    # reconstruction algorithm is based on the edges (and thus runs as many
    # times as they are time stamps intervals)
    for time_stamp in reversed(time_stamps[1:]):
        graph.reconstruct_ancestors_graph(time_stamp)

    # Among the nodes with the first time stamp, there could be
    #  - some hapaxes (that where not discovered previously as being some
    #    ancestor of a later time stamp,
    #  - some starts that must inform their descendants of their creation_date
    # Deal with those cases
    origin_time_stamp = time_stamps[0]
    recent_nodes = [n for n in graph.nodes
                     if n.get_time_stamp() == origin_time_stamp]
    for node in recent_nodes:
        if node.is_unknown():
            # The nodes, with the first time stamp, that are left without a
            # stated status are hapaxes and must be labeled as such:
            node.set_hapax(origin_time_stamp)
        elif node.is_start():
            descendants = node.get_direct_descendants()
            if not descendants:
                print("Starting node with origin time stamp and no descendants")
                pprint(vars(node))
                sys.exit(1)
            for descendant in descendants:
                # The descendants should already know about the existence of
                # the present node as being their ancestor (since this
                # information should have been discovered at the previous
                # round i.e. when those descendants where looking for their
                # own ancestor). Assert this is the case:
                if node not in descendant.get_ancestors():
                    print("Some descendants don't know their ancestor!?")
                    sys.exit(1)
                # We are thus left with informing them of the time_stamp
                descendant.set_creation_date_recursive(origin_time_stamp)
                descendant.assert_status_coherence()
        else:
            # All other cases are pathological:
            print("The following node with origin time stamp is buggy:")
            pprint(vars(node))
            sys.exit(1)

    # Collect the buildings by singling out their respective lineage
    lineage_nodes = list()
    for node in graph.nodes:
        if node.is_unknown():
            print("A node with unknown status was found:")
            pprint(vars(node))
            sys.exit(1)
        if node.is_link() or node.is_start():
            # Link and start nodes are part of an historical lineage
            # that must have an end. We will save the associated
            # information by considering the corresponding end node
            continue
        pprint(vars(node))
        lineage_nodes.append(node)


if __name__ == '__main__':
    args = ParseCommandLine()
    process_temporal_data(args)
    # cursor = open_data_base(args)
    # tileset = from_3dcitydb(cursor, args)
    # cursor.close()
    # tileset.write_to_directory('junk')
