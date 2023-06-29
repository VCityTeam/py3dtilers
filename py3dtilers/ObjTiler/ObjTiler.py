from ..Common import Tiler
from .obj import Objs


class ObjTiler(Tiler):

    def __init__(self):
        super().__init__()
        self.supported_extensions = ['.obj', '.OBJ']

    def get_output_dir(self):
        """
        Return the directory name for the tileset.
        """
        if self.args.output_dir is None:
            return "obj_tilesets"
        else:
            return self.args.output_dir

    def from_obj_directory(self):
        """
        Create a tileset from OBJ files.
        :return: a tileset.
        """
        if self.args.as_lods:
            self.files.reverse()
        objects = Objs.retrieve_objs(self.files, self.args.with_texture)

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

    tileset = obj_tiler.from_obj_directory()
    if tileset is not None:
        print("Writing tileset in", obj_tiler.get_output_dir())
        tileset.write_as_json(obj_tiler.get_output_dir())


if __name__ == '__main__':
    main()
