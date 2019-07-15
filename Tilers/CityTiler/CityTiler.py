import argparse
import numpy as np

from py3dtiles import B3dm, BatchTable, BoundingVolumeBox, GlTF
from py3dtiles import Tile, TileSet

from kd_tree import kd_tree
from database_accesses import open_data_base, retrieve_geometries,\
                              get_buildings_from_3dcitydb
from database_accesses_batch_table_hierarchy import create_batch_table_hierarchy


def ParseCommandLine():
    # arg parse
    descr = '''A small utility that build a 3DTiles tileset out of the content
               of a 3DCityDB database.'''
    parser = argparse.ArgumentParser(description=descr)
    parser.add_argument('db_config_path',
                        nargs='?',
                        default='CityTilerDBConfig.yml',
                        type=str,  # why precise this if it is the default config ?
                        help='Path to the database configuration file')
    parser.add_argument('--with_BTH',
                        dest='with_BTH',
                        action='store_true',
                        help='Adds a Batch Table Hierachy when defined')
    return parser.parse_args()


def create_tile_content(cursor, buildings, args):
    """
    :param cursor: a database access cursor
    :param buildings: the buildings of the tile.
    :param offset: the offset (a a 3D "vector" of floats) by which the
                   geographical coordinates should be translated (the
                   computation is done at the GIS level)
    :type args: CLI arguments as obtained with an ArgumentParser. Used to
                determine whether to define attach an optional
                BatchTable or possibly a BatchTableHierachy
    :rtype: a TileContent in the form a B3dm.
    """

    # Get building ids and the centroid of the tile which is the offset
    buildingIds = tuple([building.get_database_id() for building in buildings])
    offset = buildings.getCentroid()

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
    transform = np.array([1, 0,  0, 0,
                          0, 0, -1, 0,
                          0, 1,  0, 0,
                          0, 0,  0, 1])
    gltf = GlTF.from_binary_arrays(arrays, transform)

    # Create a batch table and add the database ID of each building to it
    bt = BatchTable()

    databseIds = []
    for building in buildings:
        databseIds.append(building.get_database_id())

    bt.add_property_from_array("cityobject.database_id", databseIds)

    # When required attach an extension to the batch table
    if args.with_BTH:
        bth = create_batch_table_hierarchy(cursor, buildingIds)
        bt.add_extension(bth)

    # Eventually wrap the geometries together with the optional
    # BatchTableHierarchy within a B3dm:
    return B3dm.from_glTF(gltf, bt)


def from_3dcitydb(cursor, args):
    """
    :type args: CLI arguments as obtained with an ArgumentParser.
    """

    cityobjects = get_buildings_from_3dcitydb(cursor)
    cityobjects.extend(get_reliefs_from_3dcitydb(cursor))

    # Lump out buildings in pre_tiles based on a 2D-Tree technique:
    pre_tiles = kd_tree(cityobjects, 200)

    tileset = TileSet()
    for tile_buildings in pre_tiles:
        tile = Tile()
        tile.set_geometric_error(500)

        # Construct the tile content and attach it to the new Tile:
        tile_content_b3dm = create_tile_content(cursor, tile_buildings, args)
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
        centroid = tile_buildings.getCentroid()
        bounding_box.translate([- centroid[i] for i in range(0,3)])
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
    origin  = 'This tileset is the result of Py3DTiles {__file__} script '
    origin += 'run with data extracted from database {database_name} '
    origin += ' obtained from server {server_ip}.'
    tileset.add_asset_extras(origin)

    return tileset


def main():
    """
    :return: no return value

    this function create a repository name "junk" were tilesets are
    stored.
    """
    args = ParseCommandLine()  # args is a NameSpace object instance
    cursor = open_data_base(args.db_config_path)  # cursor is a psycopg2 object returned by cursor() method
    tileset = from_3dcitydb(cursor, args)
    cursor.close()
    tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
    tileset.write_to_directory('junk')


if __name__ == '__main__':
    main()
