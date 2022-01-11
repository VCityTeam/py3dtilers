import sys
import numpy as np

from py3dtiles import TilesetReader, TriangleSoup
from ..Common import Tiler, ObjectsToTile, ObjectToTile


class TilesetTiler(Tiler):

    def __init__(self):
        super().__init__()

        # adding positional arguments
        self.parser.add_argument('--path',
                                 nargs=1,
                                 type=str,
                                 help='Path to a geojson file or a directory containing geojson files')

    def parse_command_line(self):
        super().parse_command_line()

        if(self.args.path is None):
            print("Please provide a path to a tileset.json file.")
            print("Exiting")
            sys.exit(1)

    def parse_triangle_soup(self, triangle_soup):
        triangles = triangle_soup.triangles[0]
        uvs = []
        vertex_ids = vertex_ids = [[0]]
        if len(triangle_soup.triangles) > 2:
            uvs = triangle_soup.triangles[1]
            vertex_ids = triangle_soup.triangles[2]
        elif len(triangle_soup.triangles) == 2:
            if len(triangle_soup.triangles[1]) == len(triangle_soup.triangles[0]):
                uvs = triangle_soup.triangles[1]
            else:
                vertex_ids = triangle_soup.triangles[1]

        triangle_dict = dict()
        for index, triangle in enumerate(triangles):
            id = vertex_ids[(3 * index) % len(vertex_ids)][0]

            if id not in triangle_dict:
                triangle_dict[id] = TriangleSoup()
                triangle_dict[id].triangles.append(list())
                if uvs:
                    triangle_dict[id].triangles.append(list())

            triangle_dict[id].triangles[0].append(triangle)
            if uvs:
                triangle_dict[id].triangles[1].append(uvs[index])

        objects = list()
        for id in triangle_dict:
            feature = ObjectToTile(str(id))
            feature.geom = triangle_dict[id]
            feature.set_box()
            objects.append(feature)

        return ObjectsToTile(objects)

    def tileset_to_objectstotile(self, tileset):
        all_tiles = tileset.get_root_tile().get_children()
        objects = list()
        for tile in all_tiles:
            ts = TriangleSoup.from_glTF(tile.get_content().body.glTF)
            centroid = np.array(tile.get_transform()[12:15], dtype=np.float32) * -1
            objects_to_tile = self.parse_triangle_soup(ts)
            objects_to_tile.translate_objects(centroid)
            objects.append(objects_to_tile)
        return ObjectsToTile(objects)

    def from_tileset(self, tileset):
        objects = self.tileset_to_objectstotile(tileset)

        return self.create_tileset_from_geometries(objects)


def main():

    tiler = TilesetTiler()
    tiler.parse_command_line()
    path = tiler.args.path[0]

    reader = TilesetReader()
    tileset_1 = reader.read_tileset(path)
    tileset_2 = tiler.from_tileset(tileset_1)

    tileset_1.write_to_directory("tileset_reader_output/tileset_1/")
    tileset_2.write_to_directory("tileset_reader_output/tileset_2/")


if __name__ == '__main__':
    main()
