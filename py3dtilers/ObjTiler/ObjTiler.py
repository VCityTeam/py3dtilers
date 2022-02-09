import os
import sys

from ..Common import Tiler
from .obj import Objs


class ObjTiler(Tiler):

    def __init__(self):
        super().__init__()

        # adding positional arguments
        self.parser.add_argument('--paths',
                                 nargs='*',
                                 type=str,
                                 help='path to the database configuration file')

    def parse_command_line(self):
        super().parse_command_line()

        if(self.args.paths is None):
            print("Please provide a path to a directory "
                  "containing some obj files or multiple directories")
            print("Exiting")
            sys.exit(1)

    def from_obj_directory(self, path):
        """
        Create a tileset from OBJ files.
        :param path: a path to a directory

        :return: a tileset.
        """

        objects = Objs.retrieve_objs(path)

        if(len(objects) == 0):
            print("No .obj found in " + path)
            return None
        else:
            print(str(len(objects)) + " .obj parsed")

        return self.create_tileset_from_geometries(objects)

    def get_folder_name(self, path):
        """
        Create a folder name from the path of an OBJ file.
        :param path: a path to an OBJ file

        :return: the path/name of a folder
        """
        print(path[-1])
        if(path[-1] == '\\') or (path[-1] == '\\'):
            path = path[:-1]
        folder_name = path.split('/')[-1]
        folder_name = path.split('\\')[-1]
        return folder_name


def main():
    """
    Run the ObjTiler, which creates either:
    - a repository named "obj_tileset" where the
    tileset is stored if the directory does only contains obj files.
    - or a repository named "obj_tilesets" that contains all tilesets are stored
    created from sub_directories
    and a classes.txt that contains the name of all tilesets
    :return: no return value
    """
    obj_tiler = ObjTiler()
    obj_tiler.parse_command_line()
    paths = obj_tiler.args.paths

    for path in paths:
        if(os.path.isdir(path)):
            print("Writing " + path)
            folder_name = obj_tiler.get_folder_name(path)
            obj_tiler.create_directory("obj_tilesets/" + folder_name)
            tileset = obj_tiler.from_obj_directory(path)
            if(tileset is not None):
                print("tileset in obj_tilesets/" + folder_name)
                tileset.write_to_directory("obj_tilesets/" + folder_name)


if __name__ == '__main__':
    main()
