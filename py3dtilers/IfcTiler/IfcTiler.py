import logging
import time
from ..Common import Tiler, Groups
from .ifcObjectGeom import IfcObjectsGeom


class IfcTiler(Tiler):

    def __init__(self):
        super().__init__()
        self.supported_extensions = ['.ifc', '.IFC']

        self.parser.add_argument('--grouped_by',
                                 nargs='?',
                                 default='IfcTypeObject',
                                 choices=['IfcTypeObject', 'IfcGroup', 'IfcSpace'],
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

    def from_ifc(self, grouped_by, with_BTH):
        """
        :return: a tileset.
        """
        objects = []
        for ifc_file in self.files:
            print("Reading " + str(ifc_file))
            if grouped_by == 'IfcTypeObject':
                pre_tileset = IfcObjectsGeom.retrievObjByType(ifc_file, with_BTH)
            elif grouped_by == 'IfcGroup':
                pre_tileset = IfcObjectsGeom.retrievObjByGroup(ifc_file, with_BTH)
            elif grouped_by == 'IfcSpace':
                pre_tileset = IfcObjectsGeom.retrievObjBySpace(ifc_file, with_BTH)

            objects.extend([objs for objs in pre_tileset.values() if len(objs) > 0])
        groups = Groups(objects).get_groups_as_list()

        return self.create_tileset_from_groups(groups, "batch_table_hierarchy" if with_BTH else None)


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
    tileset = ifc_tiler.from_ifc(args.grouped_by, args.with_BTH)

    if tileset is not None:
        tileset.write_as_json(ifc_tiler.get_output_dir())
    logging.info("--- %s seconds ---" % (time.time() - start_time))


if __name__ == '__main__':
    main()
