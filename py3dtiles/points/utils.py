import numpy as np
import os
from enum import Enum
from io import StringIO


def profile(func):
    from line_profiler import LineProfiler
    def wrapper(*args, **kwargs):
        lp = LineProfiler()
        deco = lp(func)
        res = deco(*args, **kwargs)
        s = StringIO()
        lp.print_stats(stream=s)
        print(s.getvalue())
        return res
    return wrapper


class SubdivisionType(Enum):
    OCTREE = 1
    QUADTREE = 2


def name_to_filename(working_dir, nameb, suffix = ''):
    name = nameb.decode('ascii')
    fullpath = [name[i:i+8] for i in range(0, len(name), 8)] if name else ['']
    folder = '{}/{}/'.format(
        working_dir,
        '/'.join(fullpath[:-1]))

    if not os.path.exists(folder):
        try:
            os.makedirs(folder, exist_ok=True)
        except OSError as exc:
            print(exc)

    filename = '{}r{}{}'.format(folder, fullpath[-1], suffix)
    return filename


def compute_spacing(aabb):
    return float(np.linalg.norm(aabb[1] - aabb[0]) / 125)


def aabb_size_to_subdivision_type(size):
    if size[2] / min(size[0], size[1]) < 0.5:
        return SubdivisionType.QUADTREE
    else:
        return SubdivisionType.OCTREE


def split_aabb(aabb, index, force_quadtree=False):
    half = (aabb[1] - aabb[0]) * 0.5
    t = aabb_size_to_subdivision_type(half)

    new_aabb = np.array([np.copy(aabb[0]), aabb[0] + half])
    if index & 4:
        new_aabb[0][0] += half[0]
        new_aabb[1][0] += half[0]
    if index & 2:
        new_aabb[0][1] += half[1]
        new_aabb[1][1] += half[1]

    if force_quadtree or t == SubdivisionType.QUADTREE:
        new_aabb[1][2] += half[2]
    elif index & 1:
        new_aabb[0][2] += half[2]
        new_aabb[1][2] += half[2]

    return new_aabb


def make_aabb_cubic(aabb):
    s = max(aabb[1] - aabb[0])
    aabb[1][0] = aabb[0][0] + s
    aabb[1][1] = aabb[0][1] + s
    aabb[1][2] = aabb[0][2] + s
    return aabb


def node_from_name(name, parent_aabb, parent_spacing):
    from .node import Node
    spacing = parent_spacing * 0.5
    aabb = split_aabb(parent_aabb, int(name[-1])) if len(name) > 0 else parent_aabb
    # let's build a new Node
    return Node(name, aabb, spacing)
