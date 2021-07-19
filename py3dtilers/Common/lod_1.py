import numpy as np
from ..Common import ObjectToTile
# from scipy.spatial import ConvexHull
from alphashape import alphashape


class FootPrint():
    def __init__(self, points, min_height, max_height):
        self.points = points
        self.min_height = min_height
        self.max_height = max_height


def get_footprint(object_to_tile, override_points=False, other_points=None):
    geom_triangles = object_to_tile.geom.triangles
    points = list()
    minZ = np.Inf
    average_maxZ = 0
    for triangles in geom_triangles:
        maxZ = np.NINF
        for triangle in triangles:
            for point in triangle:
                if len(point) >= 3:
                    points.append([point[0], point[1]])
                    if point[2] < minZ:
                        minZ = point[2]
                    if point[2] > maxZ:
                        maxZ = point[2]
        average_maxZ += maxZ
    average_maxZ /= len(geom_triangles)
    if override_points:
        points = other_points
    else:
        # hull = ConvexHull(points)
        # points = [[points[i][0], points[i][1], minZ] for i in reversed(hull.vertices)]
        hull = alphashape(points, 0.)
        points = hull.exterior.coords[:-1]
    return FootPrint(points, minZ, average_maxZ)


def create_triangles(vertices, length):
    # Contains the triangles vertices. Used to create 3D tiles
    triangles = np.ndarray(shape=(length * 4, 3, 3))
    k = 0
    # Triangles in lower and upper faces
    for j in range(1, length + 1):
        # Lower
        triangles[k] = [vertices[0], vertices[j], vertices[(j % length) + 1]]
        # Upper
        triangles[k + 1] = [vertices[(length + 1)], vertices[(length + 1) + (j % length) + 1], vertices[(length + 1) + j]]
        k += 2
    # Triangles in side faces
    for i in range(1, length + 1):
        triangles[k] = [vertices[i], vertices[(length + 1) + i], vertices[(length + 1) + (i % length) + 1]]
        triangles[k + 1] = [vertices[i], vertices[(length + 1) + (i % length) + 1], vertices[(i % length) + 1]]
        k += 2
    return triangles


def create_vertices(footprint):
    points = footprint.points
    minZ = footprint.min_height
    maxZ = footprint.max_height
    length = len(points)
    vertices = np.ndarray(shape=(2 * (length + 1), 3))
    sum_x = np.sum([point[0] for point in points])
    sum_y = np.sum([point[1] for point in points])
    centroid = [sum_x / length, sum_y / length, minZ]
    # Set bottom center vertice value
    vertices[0] = centroid
    # Set top center vertice value
    vertices[length + 1] = [centroid[0], centroid[1], maxZ]
    # For each coordinates, add a vertice at the coordinates and a vertice above at the same coordinates but with a Z-offset
    for i in range(0, length):
        vertices[i + 1] = [points[i][0], points[i][1], minZ]
        vertices[i + length + 2] = [points[i][0], points[i][1], maxZ]
    return vertices


def get_lod1(object_to_tile, override_points=False, other_points=None):
    footprint = get_footprint(object_to_tile, override_points, other_points)
    vertices = create_vertices(footprint)
    triangles = create_triangles(vertices, len(footprint.points))
    lod1_object = ObjectToTile(str(object_to_tile.get_id()) + "_lod1")
    lod1_object.geom.triangles.append(triangles)
    lod1_object.set_box()
    return lod1_object
