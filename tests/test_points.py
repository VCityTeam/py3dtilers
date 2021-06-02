import pytest
import numpy as np
from numpy.testing import assert_array_equal

from py3dtiles.points.points_grid import Grid
from py3dtiles.points.node import Node
from py3dtiles.points.utils import compute_spacing
from py3dtiles.points.distance import is_point_far_enough

# test point
xyz = np.array([0.25, 0.25, 0.25], dtype=np.float32)
to_insert = np.array([[0.25, 0.25, 0.25]], dtype=np.float32)
xyz2 = np.array([0.6, 0.6, 0.6], dtype=np.float32)
rgb = np.zeros((1, 3), dtype=np.uint8)
sample_points = np.array([[x / 30, x / 30, x / 30] for x in range(30)], dtype=np.float32)


@pytest.fixture
def node():
    bbox = np.array([[0, 0, 0], [2, 2, 2]])
    return Node('noeud', bbox, compute_spacing(bbox))


@pytest.fixture
def grid(node):
    return Grid(node)


def test_grid_insert(grid, node):
    assert grid.insert(
        node.aabb[0], node.inv_aabb_size, to_insert, rgb)[0].shape[0] == 0
    assert grid.insert(
        node.aabb[0], node.inv_aabb_size, to_insert, rgb)[0].shape[0] == 1


def test_grid_insert_perf(grid, node, benchmark):
    benchmark(grid.insert, node.aabb[0], node.inv_aabb_size, to_insert, rgb)


def test_grid_getpoints(grid, node):
    grid.insert(
        node.aabb[0], node.inv_aabb_size, to_insert, rgb)
    points = grid.get_points(True)
    ref = np.append(to_insert.view(np.uint8), rgb)
    assert_array_equal(points, ref)


def test_grid_getpoints_perf(grid, node, benchmark):
    assert grid.insert(
        node.aabb[0], node.inv_aabb_size, to_insert, rgb)[0].shape[0] == 0
    benchmark(grid.get_points, True)


def test_grid_get_point_count(grid, node):
    grid.insert(
        node.aabb[0], node.inv_aabb_size, to_insert, rgb)
    assert len(grid.get_points(False)) == 1 * (3 * 4)
    grid.insert(
        node.aabb[0], node.inv_aabb_size, to_insert, rgb)
    assert len(grid.get_points(False)) == 1 * (3 * 4)


def test_is_point_far_enough():
    points = np.array(
        [
            [1, 1, 1],
            [0.2, 0.2, 0.2],
            [0.4, 0.4, 0.4],
        ], dtype=np.float32)
    assert not is_point_far_enough(points, xyz, 0.25 ** 2)
    assert is_point_far_enough(points, xyz2, 0.25 ** 2)


def test_is_point_far_enough_perf(benchmark):
    benchmark(is_point_far_enough, sample_points, xyz, 0.25 ** 2)
