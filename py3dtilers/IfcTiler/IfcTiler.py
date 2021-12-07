from py3dtiles import BoundingVolumeBox

from ..Common import Tiler
from .ifcObjectGeom import IfcObjectsGeom


class IfcTiler(Tiler):

    def __init__(self):
        super().__init__()

        self.parser.add_argument('ifc_file_path',
                                 nargs='?',
                                 type=str,
                                 help='path to the ifc file')
        self.parser.add_argument('--originalUnit',
                                 nargs='?',
                                 default="m",
                                 type=str,
                                 help='original unit of the ifc file')
        self.parser.add_argument('--targetedUnit',
                                 nargs='?',
                                 default="m",
                                 type=str,
                                 help='targeted unit of the 3DTiles produced')

    def from_ifc(self, path_to_file, originalUnit, targetedUnit):
        """
        :param path: a path to a directory

        :return: a tileset.
        """

        pre_tileset, centroid = IfcObjectsGeom.retrievObjByType(path_to_file, originalUnit, targetedUnit)

        objects = [objs for objs in pre_tileset.values() if len(objs) > 0]
        objects_to_tile = IfcObjectsGeom(objects)

        return self.create_tileset_from_geometries(objects_to_tile)


def main():
    """
    :return: no return value

    this function creates an ifc tileset handling one ifc classe per tiles
    """
    ifc_tiler = IfcTiler()
    ifc_tiler.parse_command_line()
    args = ifc_tiler.args
    tileset = ifc_tiler.from_ifc(args.ifc_file_path, args.originalUnit, args.targetedUnit)

    if(tileset is not None):
        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
        tileset.write_to_directory("ifc_tileset")


if __name__ == '__main__':
    main()
