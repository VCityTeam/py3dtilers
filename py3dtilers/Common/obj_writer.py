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
        self.colors = list()
        self.vertex_indexes_dict = {}
        self.normal_indexes_dict = {}
        self._vertex_index = 0
        self._normal_index = 0
        self.nb_geometries = 0

    @property
    def vertex_index(self):
        self._vertex_index += 1
        return self._vertex_index

    @property
    def normal_index(self):
        self._normal_index += 1
        return self._normal_index

    def get_vertex_index(self, vertex, color):
        """
        Return the index associated to a vertex.
        If no index is associated to the vertex, create a new index and add the vertex to the OBJ's vertices.
        :param vertex: the vertex
        :return: the index associated to the vertex
        """
        vertex = vertex.tolist()
        if not tuple(vertex) in self.vertex_indexes_dict:
            self.vertex_indexes_dict[tuple(vertex)] = self.vertex_index
            self.vertices.append(vertex)
            self.colors.append(color)
        return self.vertex_indexes_dict[tuple(vertex)]

    def get_normal_index(self, normal):
        """
        Return the index associated to a normal.
        If no index is associated to the normal, create a new index and add the normal to the OBJ's normals.
        :param normal: the normal
        :return: the index associated to the normal
        """
        normal = normal.tolist()
        if not tuple(normal) in self.normal_indexes_dict:
            self.normal_indexes_dict[tuple(normal)] = self.normal_index
            self.normals.append(normal)
        return self.normal_indexes_dict[tuple(normal)]

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
        return np.array([0, 0, 1]) if norm == 0 else N / norm

    def add_triangle(self, triangle, color, offset=np.array([0, 0, 0])):
        """
        Add a triangle to the OBJ.
        An offset can be added to the triangle's position.
        :param triangle: the triangle
        :param color: the color of the triangle
        :param offset: a 3D point as numpy array
        """
        vertex_indexes = list()
        normal_indexes = list()

        normal = self.compute_triangle_normal(triangle)
        for vertex in triangle:
            vertex_indexes.append(self.get_vertex_index(vertex + offset, color))
            normal_indexes.append(self.get_normal_index(normal))

        self.triangles.append([vertex_indexes, normal_indexes])

    def add_geometries(self, feature_list, offset=np.array([0, 0, 0])):
        """
        Add 3D features to the OBJ.
        An offset can be added to the geometries
        :param feature_list: a FeatureList
        :param offset: a 3D point as numpy array
        """
        for geometry in feature_list:
            for triangle in geometry.get_geom_as_triangles():
                self.add_triangle(triangle, feature_list.materials[geometry.material_index].rgba, offset)

    def write_obj(self, file_name):
        """
        Write the OBJ into a file.
        :param file_name: the name of the OBJ file
        """
        Path(file_name).parent.mkdir(parents=True, exist_ok=True)
        f = open(file_name, "w")
        f.write("# " + str(file_name) + "\n")

        for vertex, color in zip(self.vertices, self.colors):
            f.write("v " + str(vertex[0]) + " " + str(vertex[1]) + " " + str(vertex[2]) + " " + str(color[0]) + " " + str(color[1]) + " " + str(color[2]) + "\n")

        for normal in self.normals:
            f.write("vn " + str(normal[0]) + " " + str(normal[1]) + " " + str(normal[2]) + "\n")

        for triangle in self.triangles:
            f.write("f " + str(int(triangle[0][0])) + "//" + str(int(triangle[1][0])) + " " + str(int(triangle[0][1])) + "//" + str(int(triangle[1][1])) + " " + str(int(triangle[0][2])) + "//" + str(int(triangle[1][2])) + "\n")
