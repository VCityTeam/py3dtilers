import os
import sys
from pathlib import Path

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

    def get_output_dir(self):
        """
        Return the directory name for the tileset.
        """
        if self.args.output_dir is None:
            return os.path.join("obj_tilesets", Path(self.current_path).name)
        else:
            return os.path.join(self.args.output_dir, Path(self.current_path).name)

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
        objects = Objs.retrieve_objs(path, self.args.with_texture)

        return self.create_tileset_from_feature_list(objects)


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
        obj_tiler.current_path = path
        if(os.path.isdir(path)):
            print("Writing " + path)
            tileset = obj_tiler.from_obj_directory(path)
            if(tileset is not None):
                print("tileset in", obj_tiler.get_output_dir())
                tileset.write_as_json(obj_tiler.get_output_dir())


if __name__ == '__main__':
    main()
