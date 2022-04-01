from pathlib import Path
import numpy as np


class ObjWriter():
    """
    A writer which write triangles from Feature instances into an OBJ file
    """

    def __init__(self):
        self.vertices = list()
        self.normals = list()
        self.triangles = list()
        self.vertex_indexes = {}
        self.index = 0
        self.centroid = [0, 0, 0]
        self.nb_geometries = 0

    def get_centroid(self):
        """
        Compute and return the normalized centroid of the OBJ.
        :return: the centroid
        """
        self.centroid[:] = [c / self.nb_geometries for c in self.centroid]
        return self.centroid

    def add_to_centroid(self, geom_centroid):
        """
        Add the centroid of a geometry to the centroid of the OBJ.
        :param geom_centroid: the centroid of the geometry
        """
        self.nb_geometries += 1
        for i, coord in enumerate(geom_centroid):
            self.centroid[i] += coord

    def get_index(self):
        """
        Return an index for new vertex.
        :return: the index
        """
        self.index += 1
        return self.index

    def get_vertex_index(self, vertex, normal):
        """
        Return the index associated to a vertex.
        If no index is associated to the vertex, create a new index and add the vertex and its normal to the OBJ's vertices/normals.
        :param vertex: the vertex
        :param normal: the normal of the vertex

        :return: the index associated to the vertex
        """
        vertex = vertex.tolist()
        if not tuple(vertex) in self.vertex_indexes:
            self.vertex_indexes[tuple(vertex)] = self.get_index()
            self.vertices.append(vertex)
            self.normals.append(normal)

        return self.vertex_indexes[tuple(vertex)]

    def compute_triangle_normal(self, triangle):
        """
        Compute the normal of a triangle
        :param triangle: a triangle
        :return: the normal vector of the triangle.
        """
        U = triangle[1] - triangle[0]
        V = triangle[2] - triangle[0]
        N = np.cross(U, V)
        norm = np.linalg.norm(N)
        return np.array([0, 0, 1], dtype=np.float32) if norm == 0 else N / norm

    def add_triangle(self, triangle):
        """
        Add a triangle to the OBJ.
        :param triangle: the triangle
        """
        indexes = list()
        normal = self.compute_triangle_normal(triangle)
        for vertex in triangle:
            indexes.append(self.get_vertex_index(vertex, normal))
        self.triangles.append(indexes)

    def add_geometries(self, feature_list):
        """
        Add 3D features to the OBJ.
        :param feature_list: a FeatureList
        """
        for geometry in feature_list:
            self.add_to_centroid(geometry.get_centroid())
            for triangle in geometry.get_geom_as_triangles():
                self.add_triangle(triangle)

    def write_obj(self, file_name):
        """
        Write the OBJ into a file.
        :param file_name: the name of the OBJ file
        """
        centroid = self.get_centroid()
        Path(file_name).parent.mkdir(parents=True, exist_ok=True)
        f = open(file_name, "w")
        f.write("# " + str(file_name) + "\n")

        for vertex in self.vertices:
            f.write("v " + str(vertex[0] - centroid[0]) + " " + str(vertex[1] - centroid[1]) + " " + str(vertex[2] - centroid[2]) + "\n")

        for normal in self.normals:
            f.write("vn " + str(normal[0]) + " " + str(normal[1]) + " " + str(normal[2]) + "\n")

        for triangle in self.triangles:
            f.write("f " + str(int(triangle[0])) + "/" + str(int(triangle[0])) + " " + str(int(triangle[1])) + "/" + str(int(triangle[1])) + " " + str(int(triangle[2])) + "/" + str(int(triangle[2])) + "\n")
