import unittest
from py3dtiles import BoundingVolumeBox
import numpy as np

from py3dtilers.Common.tileset_creation import create_tileset
from py3dtilers.Common.object_to_tile import ObjectToTile, ObjectsToTile


class Test_Tile(unittest.TestCase):

    def test_kd_tree(self):
        triangles = [[np.array([1843366, 5174473, 200], dtype=np.float32),
                      np.array([1843466, 5174373, 400], dtype=np.float32),
                      np.array([1843566, 5174473, 200], dtype=np.float32)],

                     [np.array([1843566, 5174473, 200], dtype=np.float32),
                      np.array([1843466, 5174373, 400], dtype=np.float32),
                      np.array([1843566, 5174273, 200], dtype=np.float32)],

                     [np.array([1843566, 5174273, 200], dtype=np.float32),
                      np.array([1843466, 5174373, 400], dtype=np.float32),
                      np.array([1843366, 5174273, 200], dtype=np.float32)],

                     [np.array([1843366, 5174273, 200], dtype=np.float32),
                      np.array([1843466, 5174373, 400], dtype=np.float32),
                      np.array([1843366, 5174473, 200], dtype=np.float32)],

                     [np.array([1843366, 5174473, 200], dtype=np.float32),
                      np.array([1843566, 5174473, 200], dtype=np.float32),
                      np.array([1843366, 5174273, 200], dtype=np.float32)],

                     [np.array([1843566, 5174473, 200], dtype=np.float32),
                      np.array([1843566, 5174273, 200], dtype=np.float32),
                      np.array([1843366, 5174273, 200], dtype=np.float32)]]

        object_to_tile = ObjectToTile("kd_tree")
        object_to_tile.geom.triangles.append(triangles)
        object_to_tile.set_box()

        objects_to_tile = ObjectsToTile([object_to_tile])

        tileset = create_tileset(objects_to_tile)

        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())

        tileset.write_to_directory('tests/test_lod_tree_tilesets/kd_tree')

    def test_lod1(self):
        triangles = [[np.array([1843366, 5174473, 200], dtype=np.float32),
                      np.array([1843466, 5174373, 400], dtype=np.float32),
                      np.array([1843566, 5174473, 200], dtype=np.float32)],

                     [np.array([1843566, 5174473, 200], dtype=np.float32),
                      np.array([1843466, 5174373, 400], dtype=np.float32),
                      np.array([1843566, 5174273, 200], dtype=np.float32)],

                     [np.array([1843566, 5174273, 200], dtype=np.float32),
                      np.array([1843466, 5174373, 400], dtype=np.float32),
                      np.array([1843366, 5174273, 200], dtype=np.float32)],

                     [np.array([1843366, 5174273, 200], dtype=np.float32),
                      np.array([1843466, 5174373, 400], dtype=np.float32),
                      np.array([1843366, 5174473, 200], dtype=np.float32)],

                     [np.array([1843366, 5174473, 200], dtype=np.float32),
                      np.array([1843566, 5174473, 200], dtype=np.float32),
                      np.array([1843366, 5174273, 200], dtype=np.float32)],

                     [np.array([1843566, 5174473, 200], dtype=np.float32),
                      np.array([1843566, 5174273, 200], dtype=np.float32),
                      np.array([1843366, 5174273, 200], dtype=np.float32)]]

        object_to_tile = ObjectToTile("lod1")
        object_to_tile.geom.triangles.append(triangles)
        object_to_tile.set_box()

        objects_to_tile = ObjectsToTile([object_to_tile])

        tileset = create_tileset(objects_to_tile, also_create_lod1=True)

        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())

        tileset.write_to_directory('tests/test_lod_tree_tilesets/lod1')

    def test_loa(self):
        triangles = [[np.array([1843366, 5174473, 200], dtype=np.float32),
                      np.array([1843466, 5174373, 400], dtype=np.float32),
                      np.array([1843566, 5174473, 200], dtype=np.float32)],

                     [np.array([1843566, 5174473, 200], dtype=np.float32),
                      np.array([1843466, 5174373, 400], dtype=np.float32),
                      np.array([1843566, 5174273, 200], dtype=np.float32)],

                     [np.array([1843566, 5174273, 200], dtype=np.float32),
                      np.array([1843466, 5174373, 400], dtype=np.float32),
                      np.array([1843366, 5174273, 200], dtype=np.float32)],

                     [np.array([1843366, 5174273, 200], dtype=np.float32),
                      np.array([1843466, 5174373, 400], dtype=np.float32),
                      np.array([1843366, 5174473, 200], dtype=np.float32)],

                     [np.array([1843366, 5174473, 200], dtype=np.float32),
                      np.array([1843566, 5174473, 200], dtype=np.float32),
                      np.array([1843366, 5174273, 200], dtype=np.float32)],

                     [np.array([1843566, 5174473, 200], dtype=np.float32),
                      np.array([1843566, 5174273, 200], dtype=np.float32),
                      np.array([1843366, 5174273, 200], dtype=np.float32)]]

        object_to_tile = ObjectToTile("loa")
        object_to_tile.geom.triangles.append(triangles)
        object_to_tile.set_box()

        objects_to_tile = ObjectsToTile([object_to_tile])

        tileset = create_tileset(objects_to_tile, also_create_loa=True, loa_path='tests/lod_tree_test_data/loa_polygons')

        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())

        tileset.write_to_directory('tests/test_lod_tree_tilesets/loa')


if __name__ == '__main__':
    unittest.main()
