from numba import jit, njit
import numpy as np


@njit("boolean(float32[:,:], float32[:], float32)", fastmath=True, nogil=True, cache=True)
def is_point_far_enough(points, tested_point, squared_min_distance):
    nbp = points.shape[0]
    farenough = True
    for i in range(nbp - 1, -1, -1):
        if (tested_point[0] - points[i][0]) ** 2 + \
           (tested_point[1] - points[i][1]) ** 2 + \
           (tested_point[2] - points[i][2]) ** 2 < squared_min_distance:
            farenough = False
            break
    return farenough


@jit(cache=True, nogil=True)
def xyz_to_child_index(xyz, aabb_center):
    test = np.greater_equal(xyz - aabb_center, 0).astype(np.int8)
    return np.sum(np.left_shift(test, [2, 1, 0]), axis=1)


@njit("int32[:](float32[:,:], int32[:], float32[:], float32[:], int32)", cache=True, nogil=True)
def xyz_to_key(xyz, cell_count, aabb_min, inv_aabb_size, shift):
    a = ((cell_count * inv_aabb_size) * (xyz - aabb_min)).astype(np.int64)
    a = np.minimum(
        np.maximum(a, 0),
        cell_count - 1)
    a[:, 1] <<= shift
    a[:, 2] <<= (2 * shift)
    return np.sum(a, axis=1).astype(np.int32)
