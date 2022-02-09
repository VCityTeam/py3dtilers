from ..Common import Tiler
from .ifcObjectGeom import IfcObjectsGeom


class IfcTiler(Tiler):

    def __init__(self):
        super().__init__()

        self.parser.add_argument('--file_path',
                                 nargs='?',
                                 type=str,
                                 help='path to the ifc file')
        self.parser.add_argument('--grouped_by',
                                 nargs='?',
                                 default='IfcTypeObject',
                                 choices=['IfcTypeObject', 'IfcGroup'],
                                 help='Either IfcTypeObject or IfcGroup (default: %(default)s)'
                                 )
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

    def from_ifc(self, path_to_file, grouped_by, originalUnit, targetedUnit):
        """
        :param path: a path to a directory

        :return: a tileset.
        """
        if(grouped_by == 'IfcTypeObject'):
            pre_tileset, centroid = IfcObjectsGeom.retrievObjByType(path_to_file, originalUnit, targetedUnit)
        elif(grouped_by == 'IfcGroup'):
            pre_tileset, centroid = IfcObjectsGeom.retrievObjByGroup(path_to_file, originalUnit, targetedUnit)

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
    tileset = ifc_tiler.from_ifc(args.file_path, args.grouped_by, args.originalUnit, args.targetedUnit)

    if(tileset is not None):
        tileset.write_to_directory("ifc_tileset")


if __name__ == '__main__':
    main()
