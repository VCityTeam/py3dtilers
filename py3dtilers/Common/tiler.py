import argparse

from .obj_writer import ObjWriter


class Tiler():

    def __init__(self):
        text = '''A small utility that build a 3DTiles tileset out of the content
        of an geojson repository'''
        self.parser = argparse.ArgumentParser(description=text)

        self.parser.add_argument('--obj',
                                 nargs='?',
                                 type=str,
                                 help='When defined, also create an .obj model of the features.\
                                    The flag must be followed by the name of the obj that will be created.')

        self.parser.add_argument('--loa',
                                 nargs='?',
                                 type=str,
                                 help='Creates a LOA when defined. The LOA is a 3D extrusion of polygons.\
                                    Objects in the same polygon are merged together.\
                                    Must be followed by the path to directory containing the polygons .geojson')

        self.parser.add_argument('--lod1',
                                 dest='lod1',
                                 action='store_true',
                                 help='Creates a LOD1 when defined. The LOD1 is a 3D extrusion of the footprint of each object.')

    def parse_command_line(self):
        return self.parser.parse_args()

    def write_geometries_as_obj(self, geometries, file_name):
        obj_writer = ObjWriter()
        obj_writer.add_geometries(geometries)
        obj_writer.write_obj(file_name)
