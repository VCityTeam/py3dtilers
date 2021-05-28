from networkx.algorithms.shortest_paths import weighted
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
        # for i in range(0,len(point)):
        #     point[i] = round(point[i],4)
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
        print("Graph created")
        return G
    
    def create_polygons(self):
        # Create mimimum cycle basis
        self.cycles = [sorted(c) for c in nx.minimum_cycle_basis(self.graph,weight = 'weight')]
        print("Cycles computed")
        # Create polygons
        for cycle in self.cycles:
            points = list()
            for index in cycle:
                vertex = Vertex.index_dict[index]
                points.append(vertex.point)
            self.polygons.append(Polygon(points))
        # points1 = [(0,0),(1843000,0),(1843000,9000000),(0,9000000)]
        # points2 = [(1843001,0),(9000000,0),(9000000,9000000),(1843001,9000000)]
        # self.polygons.append(Polygon(points1))
        # self.polygons.append(Polygon(points2))
        print("Polygons created")
        return self.polygons

def main():
    lines = [[[20, 10], [30, 10], [30, 0]],
             [[30,0], [20, 0], [10, 0], [10, 10]],
             [[10,10], [20, 10], [20, 0]]]

    p = PolygonDetector(lines)
    polygons = p.create_polygons()

    points = [(15,5),(25,5),(30,15)]

    for point in points:
        p = Point(point)
        in_polygon = False
        for polygon in polygons:
            if p.within(polygon):
                print('point',point,'in polygon',polygon)
                in_polygon = True
                break
        if not in_polygon:
            print('point',point,'not in polygon')

#main()