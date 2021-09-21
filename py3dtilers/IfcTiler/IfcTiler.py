import argparse

import numpy as np

from py3dtiles import B3dm, BatchTable, BoundingVolumeBox, GlTF
from py3dtiles import Tile, TileSet


from .ifcObjectGeom import IfcObjectsGeom


def parse_command_line():
    text = '''A small utility that build a 3DTiles tileset out of an IFC file'''
    parser = argparse.ArgumentParser(description=text)
    parser.add_argument('ifc_file_path',
                        nargs='?',
                        type=str,
                        help='path to the ifc file')
    parser.add_argument('--originalUnit',
                        nargs='?',
                        default="?",
                        type=str,
                        help='original unit of the ifc file')
    parser.add_argument('--targetedUnit',
                        nargs='?',
                        default="?",
                        type=str,
                        help='targeted unit of the 3DTiles produced')

    return parser.parse_args()


def create_tile_content(pre_tile):
    """
    :param pre_tile: an array containing objs of a single tile

    :return: a B3dm tile.
    """
    # create B3DM content

    arrays = []
    for obj in pre_tile:
        arrays.append({
            'position': obj.geom.getPositionArray(),
            'normal': obj.geom.getNormalArray(),
            'bbox': [[float(i) for i in j] for j in obj.geom.getBbox()]
        })

    # GlTF uses a y-up coordinate system whereas the geographical data (stored
    # in the 3DCityDB database) uses a z-up coordinate system convention. In
    # order to comply with Gltf we thus need to realize a z-up to y-up
    # coordinate transform for the data to respect the glTF convention. This
    # rotation gets "corrected" (taken care of) by the B3dm/gltf parser on the
    # client side when using (displaying) the data.
    # Refer to the note concerning the recommended data workflow
    # https://github.com/AnalyticalGraphicsInc/3d-tiles/tree/master/specification#gltf-transforms
    # for more details on this matter.
    transform = np.array([1, 0, 0, 0,
                          0, 0, -1, 0,
                          0, 1, 0, 0,
                          0, 0, 0, 1])
    gltf = GlTF.from_binary_arrays(arrays, transform)

    # Create a batch table and add the ID of each .obj to it
    ids = [obj.get_obj_id() for obj in pre_tile]
    classes = [obj.getIfcClasse() for obj in pre_tile]

    bt = BatchTable()
    bt.add_property_from_array("id", ids)
    bt.add_property_from_array("classe", classes)

    # Eventually wrap the geometries together with the optional
    # BatchTableHierarchy within a B3dm:
    return B3dm.from_glTF(gltf, bt)


def from_ifc(path_to_file, originalUnit, targetedUnit):
    """
    :param path: a path to a directory

    :return: a tileset.
    """

    pre_tileset, centroid = IfcObjectsGeom.retrievObjByType(path_to_file, originalUnit, targetedUnit)

    tileset = TileSet()

    for pre_tile in pre_tileset.values():
        if(len(pre_tile.objects) == 0):
            continue
        tile = Tile()
        tile.set_geometric_error(500)

        tile_content_b3dm = create_tile_content(pre_tile)
        tile.set_content(tile_content_b3dm)
        tile.set_transform(centroid)

        bounding_box = BoundingVolumeBox()
        for obj in pre_tile:
            bounding_box.add(obj.get_bounding_volume_box())
        tile.set_bounding_volume(bounding_box)

        tileset.add_tile(tile)

    return tileset


def main():
    """
    :return: no return value

    this function creates an ifc tileset handling one ifc classe per tiles
    """
    args = parse_command_line()
    tileset = from_ifc(args.ifc_file_path, args.originalUnit, args.targetedUnit)

    if(tileset is not None):
        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
        tileset.write_to_directory("ifc_tileset")


if __name__ == '__main__':
    main()
