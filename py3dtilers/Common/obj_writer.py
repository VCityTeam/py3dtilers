from os import path


class ObjWriter():
    """
    A writer which write triangles from ObjectToTile geometries into an OBJ file
    """

    def __init__(self):
        self.vertices = list()
        self.triangles = list()
        self.vertex_indexes = {}
        self.index = 0
        self.centroid = [0, 0, 0]
        self.nb_geometries = 0

    def get_centroid(self):
        self.centroid[:] = [c / self.nb_geometries for c in self.centroid]
        return self.centroid

    def add_to_centroid(self, geom_centroid):
        self.nb_geometries += 1
        for i, coord in enumerate(geom_centroid):
            self.centroid[i] += coord

    def get_index(self):
        self.index += 1
        return self.index

    def get_vertice_index(self, vertice):
        vertice = vertice.tolist()
        if not tuple(vertice) in self.vertex_indexes:
            self.vertex_indexes[tuple(vertice)] = self.get_index()
            self.vertices.append(vertice)

        return self.vertex_indexes[tuple(vertice)]

    def add_triangle(self, triangle):
        indexes = list()
        for vertice in triangle:
            indexes.append(self.get_vertice_index(vertice))
        self.triangles.append(indexes)

    def add_geometries(self, geometries):
        for geometry in geometries:
            self.add_to_centroid(geometry.get_centroid())
            for triangle in geometry.get_geom_as_triangles():
                self.add_triangle(triangle)

    def write_obj(self, file_name):
        centroid = self.get_centroid()
        f = open(path.join(file_name), "w")
        f.write("# " + file_name + "\n")

        for vertice in self.vertices:
            f.write("v " + str(vertice[0] - centroid[0]) + " " + str(vertice[1] - centroid[1]) + " " + str(vertice[2] - centroid[2]) + "\n")

        for triangle in self.triangles:
            f.write("f " + str(int(triangle[0])) + " " + str(int(triangle[1])) + " " + str(int(triangle[2])) + "\n")
