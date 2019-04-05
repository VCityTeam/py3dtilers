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


def create_tile_content(cursor, buildingIds, offset, cli_args):
    """
    :param offset: the offset (a a 3D "vector" of floats) by which the
                   geographical coordinates should be translated (the
                   computation is done at the GIS level)
    :type cli_args: CLI arguments as obtained with an ArgumentParser. Used to
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
    if cli_args.with_BTH:
        bth = create_batch_table_hierachy(cursor, buildingIds, cli_args)
        bt = BatchTable()
        bt.add_extension(bth)
    else:
        bt = None

    # Eventually wrap the geometries together with the optional
    # BatchTableHierarchy within a B3dm:
    return B3dm.from_glTF(gltf, bt)


def from_3dcitydb(cursor, cli_args):
    """
    :param cursor: a database access cursor
    :param cli_args: CLI arguments as obtained with an ArgumentParser.
    """

    # Retrieve all the buildings encountered in the 3DCityDB database together
    # with their 3D bounding box.
    cursor.execute("SELECT building.id, BOX3D(cityobject.envelope) "
                   "FROM building JOIN cityobject ON building.id=cityobject.id "
                   "WHERE building.id=building.building_root_id")
    buildings = Buildings()
    for t in cursor.fetchall():
        building_id = t[0]
        if not t[1]:
            print("Warning: droping building with id ", building_id)
            print("         because its 'cityobject.envelope' is not defined.")
            continue
        box = t[1]
        buildings.append(Building(building_id, box))

    # Lump out buildings in pre_tiles based on a 2D-Tree technique:
    pre_tiles = kd_tree(buildings, 20)

    tileset = TileSet()
    for tile_buildings in pre_tiles:
        tile = Tile()
        tile.set_geometric_error(500)

        # Construct the tile content and attach it to the new Tile:
        ids = tuple([building.getId() for building in tile_buildings])
        centroid = tile_buildings.getCentroid()
        tile_content_b3dm = create_tile_content(cursor, ids, centroid, cli_args)
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
        # An integer used as Node identifier (local to a single Graph file)
        self.id = None
        # A string used as (global) Node identifier i.e. valid across a 
        # set of Graph files
        self.globalid = None
        self.__dict__ = kwargs

        # When blending various graphs (respectively loaded from different
        # graph files), the nodes shared among such graphs (as designated
        # with their globalid) need to be reconciled. For some nodes (
        # (e.g. for nodes that are loaded when a previous node with
        # the same globalid already existed) the self.id (relative to a
        # file) will thus be lost. In order to help traceability (read
        # debugging) of the nodes, we keep the original file identifiers
        # in the following attribute:
        self.file_ids = ''

        self.creation_date = None
        self.deletion_date = None

        # Design note: we had the choice to either store the ancestor nodes
        # or to store the "ancestor edges" (that is edges that have this
        # node as target). Both choices have their respective drawbacks.
        # When storing the nodes and we need the information attached to
        # the edges we need to retrieve those edges (and the cost of retrieving
        # an edge out of its adjacent vertices is not constant in graph size).
        # And when storing the edges, retrieving the ancestors requires a
        # (constant time) walk on those edges.
        # Note that storing both is always risky because we must keep them
        # "aligned" (in sync).
        # We chose to store edges to keep the computation complexity constant.
        # The list of edges that have this node as target:
        self.ancestor_edges = list()

        # A list of edges which have this node a source. The targets of those
        # edges are thus nodes that come after in time which make them
        # descendants:
        self.descendant_edges = list()

        self.status = Node.Status.unknown
        self.set_hapax(self.get_time_stamp())

    def __str__(self):
        ret_str = f'Node: {self.globalid} (id: {self.id})\n'
        ret_str += f'  Creation date: {self.creation_date} \n'
        ret_str += f'  Deletion date: {self.deletion_date} \n'
        ret_str += f'  Status: {self.status} \n'
        if self.ancestor_edges:
            ret_str += f'  Ancestors: '
            for ancestor in self.get_ancestors():
                ret_str += ancestor.globalid + ', '
            ret_str += '\n'
        if self.descendant_edges:
            ret_str += f'  Descendants: '
            for descendant in self.get_descendants():
                ret_str += descendant.globalid + ', '
            ret_str += '\n'
        if self.file_ids != '':
            ret_str += f'  file_ids: {self.file_ids}\n'
        return ret_str

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
        ancestors = self.get_ancestors()
        descendants = self.get_descendants()
        if not ancestors and not descendants:
            if self.is_unknown():
                # No information and nothing to assert
                return
            if self.is_hapax():
                # A hapax indeed has not ancestors nor descendants
                return
            else:
                print("Only a hapax has neither ancestors nor descendants.")
                sys.exit(1)
        if ancestors and not descendants:
            if self.is_unknown():
                print("Should have been an end prior to having ancestors.")
                sys.exit(1)
            return
        if not ancestors and descendants:
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
        for descendant in self.get_descendants():
            descendant.set_creation_date_recursive(time_stamp)

    def set_deletion_date_if_later(self, time_stamp):
        if not self.deletion_date:
            self.deletion_date = time_stamp
            return
        if time_stamp > self.deletion_date:
            self.deletion_date = time_stamp

    def get_ancestors(self):
        return [edge.ancestor for edge in self.ancestor_edges]

    def add_ancestor_edge(self, ancestor_edge):
        if not ancestor_edge:
            return
        self.ancestor_edges.append(ancestor_edge)
        if self.is_hapax():
            self.set_end()
        elif self.is_start():
            self.set_link()

    def add_ancestor_edges(self, ancestor_edges_list):
        for edge in ancestor_edges_list:
            self.add_ancestor_edge(edge)

    def get_ancestor_edges(self):
        return self.ancestor_edges

    def get_descendants(self):
        """
        :return: the list of the direct descendants (no recursion done)
        """
        return [edge.descendant for edge in self.descendant_edges]

    def add_descendant_edge(self, descendant_edge):
        if not descendant_edge:
            return
        self.descendant_edges.append(descendant_edge)
        if self.is_hapax():
            self.set_start()
        elif self.is_end():
            self.set_link()

    def add_descendant_edges(self, descendant_edge_list):
        for edge in descendant_edge_list:
            self.add_descendant_edge(edge)

    def get_descendant_edges(self):
        return self.descendant_edges

    def disconnect_adjacent_edges(self):
        self.ancestor_edges = list()
        self.descendant_edges = list()

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

    def set_start(self, time_stamp=None):
        if not self.is_unknown() and not self.is_hapax():
            print("Failed to define as start.")
            sys.exit(1)
        if self.is_end():
            print("Failed to convert an end into being a start.")
            sys.exit(1)
        if self.is_link():
            print("Failed to convert a link into being a start.")
            sys.exit(1)
        self.status = Node.Status.start
        if time_stamp:
            if self.creation_date:
                print("Warning: overwriting a creation_date of a new start.")
            self.creation_date = time_stamp
        self.assert_status_coherence()

    def set_end(self, time_stamp=None):
        if not self.is_unknown() and not self.is_hapax():
            print("Failed to define as end.")
            sys.exit(1)
        if self.is_start():
            print("Failed to convert a start into being a end.")
            sys.exit(1)
        if self.is_link():
            print("Failed to convert a link into being an end.")
            sys.exit(1)
        self.status = Node.Status.end
        if time_stamp:
            if self.deletion_date:
                print("Warning: overwriting a creation_date of a new end.")
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
        # An integer used as Node identifier (local to a single Graph file)
        self.id = None
        # An integer index designating the source Node
        self.source = None
        # An integer index designating the target Node
        self.target = None
        # A string among 'replace', 'create' and 'delete'
        self.type = None
        # A sting that, when type is 'replace', is among 'fused', 'modified',
        # 're-ided' and 'subdivided'
        self.tags = None
        self.__dict__ = kwargs

        # Refer to Node.file_ids eponymous attribute for comments:
        self.file_ids = ''
        # The Node with self.source as identifier
        self.ancestor = None
        # The Node with self.target as identifier
        self.descendant = None

    def set_ancestor(self, ancestor_node):
        self.ancestor = ancestor_node
        if ancestor_node:
            ancestor_node.add_descendant_edge(self)

    def get_ancestor(self):
        return self.ancestor

    def set_descendant(self, descendant_node):
        self.descendant = descendant_node
        if descendant_node:
            descendant_node.add_ancestor_edge(self)

    def get_descendant(self):
        return self.descendant

    def is_replace(self):
        if self.type == 'replace':
            return True
        return False

    def is_unchanged(self):
        if self.is_replace() and self.tags == 'unchanged':
            return True
        return False

    def is_modified(self):
        if self.is_replace() and self.tags == 'modified':
            return True
        return False


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
        # Concerning the nodes of sub_graph we have two possibilities
        # - the node with corresponding globalid already exists in this
        #   graph in which case we need the edges to point to it
        # - the nodes is new (i.e. the node does not correspond to and existing
        #   node with the same globalid within this graph) and we need to
        #   pour/add in this graph

        # The dictionary having the sub_graph node index as key and this
        # graph node as value
        for node in sub_graph.nodes:
            existing_node = self.find_node(node.globalid)
            if existing_node:
                # We need to rewire the edges to the already existing node
                ancestor_edges = node.get_ancestor_edges()
                if ancestor_edges:
                    for edge in ancestor_edges:
                        edge.set_descendant(existing_node)
                    existing_node.add_ancestor_edges(ancestor_edges)

                descendant_edges = node.get_descendant_edges()
                if descendant_edges:
                    for edge in descendant_edges:
                        edge.set_ancestor(existing_node)
                    existing_node.add_descendant_edges(descendant_edges)

                # Keep a trace of the identification of the nodes
                existing_node.file_ids += f'{node.id}, '
            else:
                # No edge rewiring required. We simply need to add the
                # new sub-graph node to the this graph and change its
                # id to avoid id collisions:
                node.file_ids += f'{node.id}, '
                node.id = len(self.nodes) + 1
                self.nodes.append(node)

        # All sub-graph edges (rewired or not) must be kept and thus get
        # poured/blended within this graph:
        for new_edge in sub_graph.edges:
            new_edge.file_ids += f'{new_edge.id}, '
            new_edge.id = len(self.edges) + 1
            self.edges.append(new_edge)

    def add_node(self, new_node):
        self.nodes.append(new_node)

    def find_node(self, globalid):
        """
        Retrieve, when it exists, the node with the given globalid
        :param globalid: the global id that is looked for
        :return: the node with globalid when found, None otherwise
        """
        encountered = [node for node in self.nodes if node.globalid == globalid]
        if len(encountered) == 0:
            return None
        elif len(encountered) == 1:
            return encountered[0]
        else:
            print(f'Many nodes with same globalid: {globalid}')
            pprint(vars(encountered))
            sys.exit()

    def delete_node(self, node, deep_assert=False):
        """
        Assert this node has no adjacent edge that it knows about and delete
        it from the graph.
        :param node: the node to be removed
        :param deep_assert: when true, assert that no other edge of the graph
                            (that the node wouldn't know about) is pointing to
                            the argument node
        :return: True when properly deleted, sys.exit() otherwiwe
        """
        if node.get_ancestors() or node.get_descendants():
            print('Cannot delete following node with ancestors or descendants')
            pprint(vars(node))
            sys.exit()
        if deep_assert:
            for edge in self.edges:
                if edge.get_ancestor() == node or edge.get_descendant() == node:
                    print('Cannot delete following node:')
                    pprint(vars(node))
                    print('   because it is refered by following edge:')
                    pprint(vars(edge))
                    sys.exit()
        if node not in self.nodes:
            print('Cannot delete following node:')
            pprint(vars(node))
            print('   because it is not in the graph nodes.')
            sys.exit()
        self.nodes.remove(node)
        return True

    def delete_edge(self, edge, deep_assert=False):
        """
        Assert this edge has no adjacent node (that it knows about) and delete
        it from the graph.
        :param edge: the edge to be removed
        :param deep_assert: when true, assert that no other node of the graph
                            (that the edge wouldn't know about) is pointing to
                            the argument edge
        :return: True when properly deleted, sys.exit() otherwiwe
        """
        if edge.get_ancestor() or edge.get_descendant():
            print('Cannot delete following edge with an ancestor or descendant')
            pprint(vars(edge))
            sys.exit()
        if deep_assert:
            for node in self.nodes:
                if edge in node.get_ancestor_edges():
                    print('Cannot delete following edge:')
                    pprint(vars(edge))
                    print('   because it is an ancestor edge of following node:')
                    pprint(vars(node))
                    sys.exit()
                if edge in node.get_descendant_edges():
                    print('Cannot delete following edge:')
                    pprint(vars(edge))
                    print('   because it is a descendant edge of following node:')
                    pprint(vars(node))
                    sys.exit()
        self.edges.remove(edge)
        return True

    def collapse_edge_and_remove_ancestor(self, edge):
        """
        Collapse the given edge that is
         - take all the ancestor edges of the ancestor of the argument edge
           and make them ancestor edges of the descendant of that argument edge
         - remove the argument edge from the list of ancestor_edges
         - remove the argument edge from the graph
         - set the start date of the descendant of the argument edge as being
           the start date of the ancestor of the argument edge
        :param edge: the edge that should be removed
        :return: True when edge removed, sys.exit() otherwise
        """

        ancestor = edge.get_ancestor()
        descendant = edge.get_descendant()
        ancestor_edges = ancestor.get_ancestor_edges()

        # Rewire the ancestor_edges to the descendant
        if ancestor_edges:
            for ancestor_edge in ancestor_edges:
                ancestor_edge.set_descendant(descendant)
            # Conversely, let the descendant now about its new ancestor edges
            descendant.add_ancestor_edges(ancestor_edges)

        # Disconnect the ancestor node from all its adjacent edges
        ancestor.disconnect_adjacent_edges()

        # We must now proceed with isolating/un-connecting the edge
        edge.set_ancestor(None)
        edge.set_descendant(None)
        descendant.get_ancestor_edges().remove(edge)

        # Both the ancestor node and the edge to be collapsed are now isolated
        # from the graph. We can proceed with their removal:
        self.delete_node(ancestor, True)
        self.delete_edge(edge, True)

        return True


class GraphMLDecoder(json.JSONDecoder):
    def __init__(self):
        json.JSONDecoder.__init__(self, object_hook=self.dict_to_object)

    def dict_to_object(self, dct):
        if 'id' in dct and 'globalid' in dct:
            return Node(**dct)
        if      'id'     in dct \
            and 'source' in dct \
            and 'target' in dct \
            and 'type'   in dct \
            and 'tags'   in dct:
            return Edge(**dct)
        return dct


def process_temporal_data(cli_args):
    graph = None
    print("Loading nodes and edges of files: ")
    # Deserialize the temporal (sub) graphs to constitute the general graph
    for temporal_graph_filename in cli_args.temporal_graph:
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
                edge.set_ancestor(current_nodes[int(edge.source)])
            if isinstance(edge.target, str):
                edge.set_descendant(current_nodes[int(edge.target)])

        # Eventually we can pour/blend the current graph with the central
        # graph
        new_sub_graph = Graph(current_nodes, current_edges)
        if not graph:
            graph = new_sub_graph
        else:
            graph.extend_with_subgraph(new_sub_graph)
        print("   ", temporal_graph_filename, ": done.")
    print("Loading of files: done.")
    print("Graph connectivity reconstruction: done.")

    # FIXME FIXME ancestor.set_deletion_date_if_later(time_stamp)
    # FIXME FIXME descendant.set_creation_date_recursive(time_stamp)
    #                 descendant.assert_status_coherence()

    print("Simplifying the graph: collapsing unchanged edges.")
    for edge in graph.edges:
        if edge.is_modified():
            graph.collapse_edge_and_remove_ancestor(edge)

    # DEBUG
    for node in graph.nodes:
        if node.is_unknown():
            print("A node with unknown status was found:")
            pprint(vars(node))
            sys.exit(1)
        print(node)


if __name__ == '__main__':
    args = ParseCommandLine()
    process_temporal_data(args)
    # cursor = open_data_base(args)
    # tileset = from_3dcitydb(cursor, args)
    # cursor.close()
    # tileset.write_to_directory('junk')
