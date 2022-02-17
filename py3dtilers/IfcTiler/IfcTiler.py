import logging
import time
from ..Common import Tiler, Groups
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
        self.parser.add_argument('--with_BTH',
                                 dest='with_BTH',
                                 action='store_true',
                                 help='Adds a Batch Table Hierarchy when defined')
                                

    def get_output_dir(self):
        """
        Return the directory name for the tileset.
        """
        if self.args.output_dir is None:
            return "ifc_tileset"
        else:
            return self.args.output_dir

    def from_ifc(self, path_to_file, grouped_by, originalUnit, targetedUnit,with_BTH):
        """
        :param path: a path to a directory

        :return: a tileset.
        """
        if(grouped_by == 'IfcTypeObject'):
            pre_tileset = IfcObjectsGeom.retrievObjByType(path_to_file)
        elif(grouped_by == 'IfcGroup'):
            pre_tileset = IfcObjectsGeom.retrievObjByGroup(path_to_file)

        objects = [objs for objs in pre_tileset.values() if len(objs) > 0]
        groups = Groups(objects).get_groups_as_list()
        return self.create_tileset_from_groups(groups)
        # objects_to_tile = IfcObjectsGeom(objects)

        # return self.create_tileset_from_geometries(objects_to_tile, "batch_table_hierarchy" if with_BTH  else None)


def main():
    """
    :return: no return value

    this function creates an ifc tileset handling one ifc classe per tiles
    """
    logging.basicConfig(filename='ifctiler.log', level=logging.INFO, filemode="w")
    start_time = time.time()
    logging.info('Started')
    ifc_tiler = IfcTiler()
    ifc_tiler.parse_command_line()
    args = ifc_tiler.args
    tileset = ifc_tiler.from_ifc(args.file_path, args.grouped_by,args.with_BTH)

    if(tileset is not None):
        tileset.write_as_json(ifc_tiler.get_output_dir())
    logging.info("--- %s seconds ---" % (time.time() - start_time))


if __name__ == '__main__':
    main()
