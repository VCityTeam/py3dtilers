import numpy as np
from numba import njit

from py3dtiles.points.utils import SubdivisionType, aabb_size_to_subdivision_type
from py3dtiles.points.distance import is_point_far_enough, xyz_to_key


@njit(fastmath=True, cache=True)
def _insert(cells_xyz, cells_rgb, aabmin, inv_aabb_size, cell_count, xyz, rgb, spacing, shift, force=False):
    keys = xyz_to_key(xyz, cell_count, aabmin, inv_aabb_size, shift)

    if force:
        # allocate this one once and for all
        for k in np.unique(keys):
            idx = np.where(keys - k == 0)
            cells_xyz[k] = np.concatenate((cells_xyz[k], xyz[idx]))
            cells_rgb[k] = np.concatenate((cells_rgb[k], rgb[idx]))
    else:
        notinserted = np.full(len(xyz), False)
        needs_balance = False

        for i in range(len(xyz)):
            k = keys[i]
            if cells_xyz[k].shape[0] == 0 or is_point_far_enough(cells_xyz[k], xyz[i], spacing):
                cells_xyz[k] = np.concatenate((cells_xyz[k], xyz[i].reshape(1, 3)))
                cells_rgb[k] = np.concatenate((cells_rgb[k], rgb[i].reshape(1, 3)))
                if cell_count[0] < 8:
                    needs_balance = needs_balance or cells_xyz[k].shape[0] > 200000
            else:
                notinserted[i] = True

        return xyz[notinserted], rgb[notinserted], needs_balance


class Grid(object):
    """docstring for Grid"""

    __slots__ = ('cell_count', 'cells_xyz', 'cells_rgb', 'spacing')

    def __init__(self, node, initial_count=3):
        super(Grid, self).__init__()
        self.cell_count = np.array([initial_count, initial_count, initial_count], dtype=np.int32)
        self.spacing = node.spacing * node.spacing

        self.cells_xyz = [np.zeros((0, 3), dtype=np.float32) for _ in range(self.max_key_value)]
        self.cells_rgb = [np.zeros((0, 3), dtype=np.uint8) for _ in range(self.max_key_value)]

    @property
    def max_key_value(self):
        return 1 << (2 * int(self.cell_count[0]).bit_length() + int(self.cell_count[2]).bit_length())

    def insert(self, aabmin, inv_aabb_size, xyz, rgb, force=False):
        return _insert(
            self.cells_xyz,
            self.cells_rgb,
            aabmin,
            inv_aabb_size,
            self.cell_count,
            xyz,
            rgb,
            self.spacing,
            int(self.cell_count[0] - 1).bit_length(), force)

    def needs_balance(self):
        if self.cell_count[0] < 8:
            for cell in self.cells_xyz:
                if cell.shape[0] > 100000:
                    return True
        return False

    def balance(self, aabb_size, aabmin, inv_aabb_size):
        t = aabb_size_to_subdivision_type(aabb_size)
        self.cell_count[0] += 1
        self.cell_count[1] += 1
        if t != SubdivisionType.QUADTREE:
            self.cell_count[2] += 1
        assert self.cell_count[0] < 9

        old_cells_xyz = self.cells_xyz
        old_cells_rgb = self.cells_rgb
        self.cells_xyz = [np.zeros((0, 3), dtype=np.float32) for _ in range(self.max_key_value)]
        self.cells_rgb = [np.zeros((0, 3), dtype=np.uint8) for _ in range(self.max_key_value)]

        for cellxyz, cellrgb in zip(old_cells_xyz, old_cells_rgb):
            self.insert(aabmin, inv_aabb_size, cellxyz, cellrgb, True)

    def get_points(self, include_rgb):
        xyz = ()
        rgb = ()
        pt = 0
        for i in range(len(self.cells_xyz)):
            xyz += ((self.cells_xyz[i]).view(np.uint8).ravel(),)
            rgb += (self.cells_rgb[i].ravel(),)
            pt += self.cells_xyz[i].shape[0]

        if include_rgb:
            res = np.concatenate((np.concatenate(xyz), np.concatenate(rgb)))
            assert len(res) == pt * (3 * 4 + 3)
            return res
        else:
            return np.concatenate(xyz)
