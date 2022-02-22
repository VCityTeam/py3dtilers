import unittest
import numpy as np
from argparse import Namespace
from pathlib import Path

from py3dtilers.Common.tiler import Tiler
from py3dtilers.Common.object_to_tile import Feature, FeatureList


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
        object_to_tile = Feature("kd_tree")
        object_to_tile.geom.triangles.append(triangles)
        object_to_tile.set_box()
        objects_to_tile = FeatureList([object_to_tile])

        tiler = Tiler()
        directory = Path('tests/tiler_test_data/tilesets/kd_tree')
        tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory)

        tileset = tiler.create_tileset_from_geometries(objects_to_tile)

        tileset.write_to_directory(directory)

    def test_lod1(self):
        object_to_tile = Feature("lod1")
        object_to_tile.geom.triangles.append(triangles)
        object_to_tile.set_box()
        objects_to_tile = FeatureList([object_to_tile])

        tiler = Tiler()
        directory = Path('tests/tiler_test_data/tilesets/lod1')
        tiler.args = Namespace(obj=None, loa=None, lod1=True, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory)

        tileset = tiler.create_tileset_from_geometries(objects_to_tile)

        tileset.write_to_directory(directory)

    def test_loa(self):
        object_to_tile = Feature("loa")
        object_to_tile.geom.triangles.append(triangles)
        object_to_tile.set_box()
        objects_to_tile = FeatureList([object_to_tile])

        tiler = Tiler()
        directory = Path('tests/tiler_test_data/tilesets/loa')
        tiler.args = Namespace(obj=None, loa=Path('tests/tiler_test_data/loa_polygons'), lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory)

        tileset = tiler.create_tileset_from_geometries(objects_to_tile)

        tileset.write_to_directory(directory)

    def test_change_crs(self):
        object_to_tile = Feature("change_crs")
        object_to_tile.geom.triangles.append(triangles)
        object_to_tile.set_box()
        objects_to_tile = FeatureList([object_to_tile])

        tiler = Tiler()
        directory = Path('tests/tiler_test_data/tilesets/change_crs')
        tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:4171', offset=[0, 0, 0], with_texture=False, output_dir=directory)

        tileset = tiler.create_tileset_from_geometries(objects_to_tile)

        tileset.write_to_directory(directory)

    def test_offset(self):
        object_to_tile = Feature("offset")
        object_to_tile.geom.triangles.append(triangles)
        object_to_tile.set_box()
        objects_to_tile = FeatureList([object_to_tile])

        tiler = Tiler()
        directory = Path('tests/tiler_test_data/tilesets/offset')
        tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[100, 100, -200], with_texture=False, output_dir=directory)

        tileset = tiler.create_tileset_from_geometries(objects_to_tile)

        tileset.write_to_directory(directory)

    def test_offset_centroid(self):
        object_to_tile = Feature("offset_centroid")
        object_to_tile.geom.triangles.append(triangles)
        object_to_tile.set_box()
        objects_to_tile = FeatureList([object_to_tile])

        tiler = Tiler()
        directory = Path('tests/tiler_test_data/tilesets/offset_centroid')
        tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=['centroid'], with_texture=False, output_dir=directory)

        tileset = tiler.create_tileset_from_geometries(objects_to_tile)

        tileset.write_to_directory(directory)

    def test_scale(self):
        object_to_tile = Feature("scale")
        object_to_tile.geom.triangles.append(triangles)
        object_to_tile.set_box()
        objects_to_tile = FeatureList([object_to_tile])

        tiler = Tiler()
        directory = Path('tests/tiler_test_data/tilesets/scale')
        tiler.args = Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, scale=10, output_dir=directory)

        tileset = tiler.create_tileset_from_geometries(objects_to_tile)

        tileset.write_to_directory(directory)

    def test_obj(self):
        object_to_tile = Feature("scale")
        object_to_tile.geom.triangles.append(triangles)
        object_to_tile.set_box()
        objects_to_tile = FeatureList([object_to_tile])

        obj_name = Path('tests/tiler_test_data/junk/cube.obj')

        tiler = Tiler()
        directory = Path('tests/tiler_test_data/tilesets/scale')
        tiler.args = Namespace(obj=obj_name, loa=None, lod1=False, crs_in='EPSG:3946', crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, output_dir=directory)

        tileset = tiler.create_tileset_from_geometries(objects_to_tile)

        tileset.write_to_directory(directory)


if __name__ == '__main__':
    unittest.main()
