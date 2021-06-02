from shapely.geometry import Point, Polygon
import networkx as nx
import math

class Vertex:
    index = 0
    index_dict = {}
    def __init__(self, point):
        self.point = point
        self.index = Vertex.index
        Vertex.index += 1
        Vertex.index_dict[self.index] = self

    def distance(p1,p2):
        distance = 0
        for i in range(0,min(len(p1),len(p2))):
            distance += (p1[i] - p2[i])**2
        return math.sqrt(distance)

class PolygonDetector:
    def __init__(self,lines):
        self.vertices = list()
        self.vertices_dict = {}
        self.polygons = list()
        self.cycles = []
        self.graph = self.create_graph(lines)

    # Return the vertex at the coordinates of 'point' in the dictionary
    # If the vertex doesn't exist, create it and add it to the dictionary
    def get_point(self,point):
        if tuple(point) in self.vertices_dict:
            vertex = self.vertices_dict[tuple(point)]
        else:
            vertex = Vertex(point)
            self.vertices_dict[tuple(point)] = vertex
            self.vertices.append(vertex)
        return vertex

    def create_graph(self,lines):
        G = nx.Graph()

        for line in lines:
            last_point = self.get_point(line[0])
            for i in range(1,len(line)):
                current_point = self.get_point(line[i])
                G.add_edge(last_point.index,current_point.index,weight = Vertex.distance(last_point.point,current_point.point))
                last_point = current_point
        # Clean graph by deleting useless vertices
        nodes_to_treat = []
        for n in list(G.nodes):
            neighbors = list(G.neighbors(n))
            if len(neighbors) <= 1:
                nodes_to_treat.append(n)
            else:
                continue
        while len(nodes_to_treat) > 0:
            node = nodes_to_treat[0]
            if not G.has_node(n):
                nodes_to_treat.remove(node)
                continue
            neighbors = list(G.neighbors(node))
            G.remove_node(node)
            nodes_to_treat.remove(node)
            for n in neighbors:
                if len(list(G.neighbors(n))) <= 1:
                    nodes_to_treat.append(n)

        print("Graph created")
        return G
    
    def create_polygons(self):
        # Create mimimum cycle basis
        self.cycles = [sorted(c) for c in nx.minimum_cycle_basis(self.graph,weight = 'weight')]
        print("Cycles computed")
        # Create polygons
        for cycle in self.cycles:
            points = self.order_points(cycle)
            self.polygons.append(Polygon(points))
        print("Polygons created")
        return self.polygons

    def order_points(self,indexes):
        points = list()
        current_index = indexes[0]
        indexes_to_treat = indexes[1:len(indexes)]
        points.append(Vertex.index_dict[current_index].point)
        while len(points) < len(indexes):
            for i in indexes_to_treat:
                if self.graph.has_edge(current_index,i):
                    points.append(Vertex.index_dict[i].point)
                    indexes_to_treat.remove(i)
                    current_index = i
                    break
        return points