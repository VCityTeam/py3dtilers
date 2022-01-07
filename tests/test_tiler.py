import unittest
from py3dtiles import BoundingVolumeBox
import numpy as np
from argparse import Namespace
import os

from py3dtilers.Common.tiler import Tiler
from py3dtilers.Common.object_to_tile import ObjectToTile, ObjectsToTile


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


class Test_Tile(unittest.TestCase):
    def test_kd_tree(self):
        object_to_tile = ObjectToTile("kd_tree")
        object_to_tile.geom.triangles.append(triangles)
        object_to_tile.set_box()
        objects_to_tile = ObjectsToTile([object_to_tile])

        tiler = Tiler()
        tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False)

        tileset = tiler.create_tileset_from_geometries(objects_to_tile)
        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
        tileset.write_to_directory('tests/tiler_test_data/tilesets/kd_tree')

    def test_lod1(self):
        object_to_tile = ObjectToTile("lod1")
        object_to_tile.geom.triangles.append(triangles)
        object_to_tile.set_box()
        objects_to_tile = ObjectsToTile([object_to_tile])

        tiler = Tiler()
        tiler.args = Namespace(obj=None, loa=None, lod1=True, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False)

        tileset = tiler.create_tileset_from_geometries(objects_to_tile)
        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())

        tileset.write_to_directory('tests/tiler_test_data/tilesets/lod1')

    def test_loa(self):
        object_to_tile = ObjectToTile("loa")
        object_to_tile.geom.triangles.append(triangles)
        object_to_tile.set_box()
        objects_to_tile = ObjectsToTile([object_to_tile])

        tiler = Tiler()
        tiler.args = Namespace(obj=None, loa='tests/tiler_test_data/loa_polygons', lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False)

        tileset = tiler.create_tileset_from_geometries(objects_to_tile)

        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())

        tileset.write_to_directory('tests/tiler_test_data/tilesets/loa')

    def test_change_crs(self):
        object_to_tile = ObjectToTile("change_crs")
        object_to_tile.geom.triangles.append(triangles)
        object_to_tile.set_box()
        objects_to_tile = ObjectsToTile([object_to_tile])

        tiler = Tiler()
        tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:4171', offset=[0, 0, 0], with_texture=False)

        tileset = tiler.create_tileset_from_geometries(objects_to_tile)

        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())

        tileset.write_to_directory('tests/tiler_test_data/tilesets/change_crs')

    def test_offset(self):
        object_to_tile = ObjectToTile("offset")
        object_to_tile.geom.triangles.append(triangles)
        object_to_tile.set_box()
        objects_to_tile = ObjectsToTile([object_to_tile])

        tiler = Tiler()
        tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[100, 100, -200], with_texture=False)

        tileset = tiler.create_tileset_from_geometries(objects_to_tile)

        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())

        tileset.write_to_directory('tests/tiler_test_data/tilesets/offset')

    def test_offset_centroid(self):
        object_to_tile = ObjectToTile("offset_centroid")
        object_to_tile.geom.triangles.append(triangles)
        object_to_tile.set_box()
        objects_to_tile = ObjectsToTile([object_to_tile])

        tiler = Tiler()
        tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=['centroid'], with_texture=False)

        tileset = tiler.create_tileset_from_geometries(objects_to_tile)

        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())

        tileset.write_to_directory('tests/tiler_test_data/tilesets/offset_centroid')

    def test_scale(self):
        object_to_tile = ObjectToTile("scale")
        object_to_tile.geom.triangles.append(triangles)
        object_to_tile.set_box()
        objects_to_tile = ObjectsToTile([object_to_tile])

        tiler = Tiler()
        tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, scale=10)

        tileset = tiler.create_tileset_from_geometries(objects_to_tile)

        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())

        tileset.write_to_directory('tests/tiler_test_data/tilesets/scale')

    def test_obj(self):
        object_to_tile = ObjectToTile("scale")
        object_to_tile.geom.triangles.append(triangles)
        object_to_tile.set_box()
        objects_to_tile = ObjectsToTile([object_to_tile])

        if not os.path.exists('tests/tiler_test_data/junk'):
            os.makedirs('tests/tiler_test_data/junk')
        obj_name = 'tests/tiler_test_data/junk/cube.obj'

        tiler = Tiler()
        tiler.args = Namespace(obj=obj_name, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False)

        tileset = tiler.create_tileset_from_geometries(objects_to_tile)

        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())

        tileset.write_to_directory('tests/tiler_test_data/tilesets/scale')


if __name__ == '__main__':
    unittest.main()
