import unittest
import numpy as np
from argparse import Namespace
from pathlib import Path

from py3dtilers.Common.tiler import Tiler
from py3dtilers.Common.feature import Feature, FeatureList


def get_default_namespace():
    return Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946',
                     crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, scale=1,
                     output_dir=None, geometric_error=[None, None, None], kd_tree_max=None)


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
        feature = Feature("kd_tree")
        feature.geom.triangles.append(triangles)
        feature.set_box()
        feature_list = FeatureList([feature])

        tiler = Tiler()
        tiler.args = get_default_namespace()
        tiler.args.output_dir = Path('tests/tiler_test_data/generated_tilesets/kd_tree')

        tileset = tiler.create_tileset_from_geometries(feature_list)

        tileset.write_as_json(tiler.args.output_dir)

    def test_lod1(self):
        feature = Feature("lod1")
        feature.geom.triangles.append(triangles)
        feature.set_box()
        feature_list = FeatureList([feature])

        tiler = Tiler()
        tiler.args = get_default_namespace()
        tiler.args.output_dir = Path('tests/tiler_test_data/generated_tilesets/lod1')
        tiler.args.lod1 = True

        tileset = tiler.create_tileset_from_geometries(feature_list)

        tileset.write_as_json(tiler.args.output_dir)

    def test_loa(self):
        feature = Feature("loa")
        feature.geom.triangles.append(triangles)
        feature.set_box()
        feature_list = FeatureList([feature])

        tiler = Tiler()
        tiler.args = get_default_namespace()
        tiler.args.output_dir = Path('tests/tiler_test_data/generated_tilesets/loa')
        tiler.args.loa = Path('tests/tiler_test_data/loa_polygons')
        tileset = tiler.create_tileset_from_geometries(feature_list)

        tileset.write_as_json(tiler.args.output_dir)

    def test_change_crs(self):
        feature = Feature("change_crs")
        feature.geom.triangles.append(triangles)
        feature.set_box()
        feature_list = FeatureList([feature])

        tiler = Tiler()
        tiler.args = get_default_namespace()
        tiler.args.output_dir = Path('tests/tiler_test_data/generated_tilesets/change_crs')
        tiler.args.crs_out = 'EPSG:4171'

        tileset = tiler.create_tileset_from_geometries(feature_list)

        tileset.write_as_json(tiler.args.output_dir)

    def test_offset(self):
        feature = Feature("offset")
        feature.geom.triangles.append(triangles)
        feature.set_box()
        feature_list = FeatureList([feature])

        tiler = Tiler()
        tiler.args = get_default_namespace()
        tiler.args.output_dir = Path('tests/tiler_test_data/generated_tilesets/offset')
        tiler.args.offset = [100, 100, -200]

        tileset = tiler.create_tileset_from_geometries(feature_list)

        tileset.write_as_json(tiler.args.output_dir)

    def test_offset_centroid(self):
        feature = Feature("offset_centroid")
        feature.geom.triangles.append(triangles)
        feature.set_box()
        feature_list = FeatureList([feature])

        tiler = Tiler()
        tiler.args = get_default_namespace()
        tiler.args.output_dir = Path('tests/tiler_test_data/generated_tilesets/offset_centroid')
        tiler.args.offset = ['centroid']

        tileset = tiler.create_tileset_from_geometries(feature_list)

        tileset.write_as_json(tiler.args.output_dir)

    def test_scale(self):
        feature = Feature("scale")
        feature.geom.triangles.append(triangles)
        feature.set_box()
        feature_list = FeatureList([feature])

        tiler = Tiler()
        tiler.args = get_default_namespace()
        tiler.args.output_dir = Path('tests/tiler_test_data/generated_tilesets/scale')
        tiler.args.scale = 10

        tileset = tiler.create_tileset_from_geometries(feature_list)

        tileset.write_as_json(tiler.args.output_dir)

    def test_obj(self):
        feature = Feature("obj")
        feature.geom.triangles.append(triangles)
        feature.set_box()
        feature_list = FeatureList([feature])

        tiler = Tiler()
        tiler.args = get_default_namespace()
        tiler.args.output_dir = Path('tests/tiler_test_data/generated_tilesets/obj')
        tiler.args.obj = Path('tests/tiler_test_data/generated_objs/cube.obj')

        tileset = tiler.create_tileset_from_geometries(feature_list)

        tileset.write_as_json(tiler.args.output_dir)

    def test_geometric_error(self):
        feature = Feature("scale")
        feature.geom.triangles.append(triangles)
        feature.set_box()
        feature_list = FeatureList([feature])

        tiler = Tiler()
        tiler.args = get_default_namespace()
        tiler.args.output_dir = Path('tests/tiler_test_data/generated_tilesets/geometric_error')
        tiler.args.geometric_error = [3, None, 200]
        tiler.args.lod1 = True
        tiler.args.loa = Path('tests/tiler_test_data/loa_polygons')

        tileset = tiler.create_tileset_from_geometries(feature_list)

        tileset.write_as_json(tiler.args.output_dir)

    def test_kd_tree_max(self):
        features = list()
        for i in range(0, 3):
            feature = Feature("kd_tree_" + str(i))
            feature.geom.triangles.append(triangles)
            feature.set_box()
            features.append(feature)
        feature_list = FeatureList(features)

        tiler = Tiler()
        tiler.args = get_default_namespace()
        tiler.args.output_dir = Path('tests/tiler_test_data/generated_tilesets/kd_tree_max')
        tiler.args.kd_tree_max = 1

        tileset = tiler.create_tileset_from_geometries(feature_list)

        tileset.write_as_json(tiler.args.output_dir)


if __name__ == '__main__':
    unittest.main()
