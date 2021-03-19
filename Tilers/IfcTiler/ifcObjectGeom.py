# -*- coding: utf-8 -*-
import sys
import numpy as np
from py3dtiles import BoundingVolumeBox, TriangleSoup
from Tilers.object_to_tile import ObjectToTile, ObjectsToTile
import ifcopenshell

import os
from os import listdir
from os.path import isfile, join
from pyproj import Transformer

def normalize(v): 
    norm = np.linalg.norm(v) 
    if norm == 0: 
        return v 
    return v / norm

def computeDirection(axis,refDirection):
    # ref to https://standards.buildingsmart.org/IFC/RELEASE/IFC2x3/FINAL/HTML/ifcgeometryresource/lexical/ifcfirstprojaxis.htm
    # and https://standards.buildingsmart.org/IFC/RELEASE/IFC2x3/FINAL/HTML/ifcgeometryresource/lexical/ifcbuildaxes.htm
    Z = normalize(axis)
    V = normalize(refDirection)
    XVec = np.multiply(np.dot(V, Z), Z)
    XAxis = normalize(np.subtract(V,XVec))
    return np.array([XAxis,np.cross(Z,XAxis),Z])



class IfcObjectGeom(ObjectToTile):
    def __init__(self,ifcObject,convertToMeter = False):
        super().__init__()

        self.id = ifcObject.GlobalId
        self.geom = TriangleSoup()
        self.convertToMeter = convertToMeter
        self.ifcObject = ifcObject
        self.ifcClasse = ifcObject.is_a()
        self.has_geom = self.parse_geom()

    def hasGeom(self):
        return self.has_geom

    def get_geom_as_triangles(self):
        return self.geom.triangles[0]

    def set_triangles(self,triangles):
        self.geom.triangles[0] = triangles

    def computeCenter(self,pointList) :
        center = np.array([0.0,0.0,0.0])
        for point in pointList :
            center += np.array([point[0],point[1],0])
        return center / len(pointList)

    def getIfcClasse(self) :
        return self.ifcClasse

    def extrudGeom(self,geom) :
        depth = geom.Depth
        extrudedDirection = geom.ExtrudedDirection.DirectionRatios
        extrudVector = np.multiply(extrudedDirection,depth)

        position = geom.Position.Location.Coordinates

        axis = [0,0,1]
        refDirection = [1,0,0]

        if (geom.Position.Axis) :
            axis = geom.Position.Axis.DirectionRatios
        
        if (geom.Position.RefDirection) :
            refDirection = geom.Position.RefDirection.DirectionRatios 

        direction = computeDirection(axis,refDirection)
        
        points = geom.SweptArea.OuterCurve.Points.CoordList
        center = self.computeCenter(points)
        
        vertexList = list()
        indexList = list()
        for point in points : 
            vertexList.append(np.array([point[0],point[1],0]))
        for point in points : 
            vertexList.append(np.array([point[0],point[1],0]) + extrudVector)    
        vertexList.append(center)            
        vertexList.append(center + extrudVector)

        for i in range(len(vertexList)) : 
            vertexList[i] = np.dot(np.array(vertexList[i]),direction) + position

        nb_points = len(points)
        i = 0
        for i in range(nb_points - 1) :
            indice = i+1
            indexList.append([indice,(nb_points * 2) + 1,indice + 1])
            indexList.append([indice + nb_points,indice + nb_points + 1,(nb_points * 2) + 2])
        
        i = 0
        for i in range(nb_points - 1) :
            indice = i+1
            indexList.append([indice,indice + 1,indice + nb_points ])
            indexList.append([indice + 1,indice + nb_points + 1,indice + nb_points])

        return vertexList, indexList

    def getPosition(self,ObjectPlacement) :
        listPosition = list()
        position = np.array(ObjectPlacement.RelativePlacement.Location.Coordinates)
        listPosition.append(position)
        placementRelTo = ObjectPlacement.PlacementRelTo
        
        while (placementRelTo) :
            if(placementRelTo.PlacesObject[0].is_a("IfcSite")):
                break
            listPosition.append(np.array(placementRelTo.RelativePlacement.Location.Coordinates))
            placementRelTo = placementRelTo.PlacementRelTo
        return listPosition

    def getDirections(self,ObjectPlacement) :
        listDirection = list()
        axis = [0,0,1]
        if (ObjectPlacement.RelativePlacement.Axis) :
            axis = ObjectPlacement.RelativePlacement.Axis.DirectionRatios
        
        refDirection = [1,0,0]
        if (ObjectPlacement.RelativePlacement.RefDirection) :
            refDirection = ObjectPlacement.RelativePlacement.RefDirection.DirectionRatios 

        listDirection.append(computeDirection(axis,refDirection))
        
        placementRelTo = ObjectPlacement.PlacementRelTo
        
        while (placementRelTo) :
            if(placementRelTo.PlacesObject[0].is_a("IfcSite")):
                break
            axis = [0,0,1]
            if (placementRelTo.RelativePlacement.Axis) :
                axis = placementRelTo.RelativePlacement.Axis.DirectionRatios
            
            refDirection = [1,0,0]
            if (placementRelTo.RelativePlacement.RefDirection) :
                refDirection = placementRelTo.RelativePlacement.RefDirection.DirectionRatios 

            listDirection.append(computeDirection(axis,refDirection))
            placementRelTo = placementRelTo.PlacementRelTo

        return listDirection

    def getElevation(self) :
        elevation = 0
        if(self.ifcObject.ContainedInStructure) :
            if(not(self.ifcObject.ContainedInStructure[0].RelatingStructure.is_a("IfcSpace"))) :
                elevation += self.ifcObject.ContainedInStructure[0].RelatingStructure.Elevation

        if(self.convertToMeter):
            elevation /= 100

        return elevation

    def parse_geom(self):
        if (not(self.ifcObject.Representation)) :
            return False
        
        representations = self.ifcObject.Representation.Representations
        
        elevation = self.getElevation()
        
        listPosition = self.getPosition(self.ifcObject.ObjectPlacement)

        listDirection = self.getDirections(self.ifcObject.ObjectPlacement)

        
        vertexList = list()
        indexList = list()
        for representation in representations :
            if(representation.RepresentationType == "MappedRepresentation") :
                representation = representation.Items[0].MappingSource.MappedRepresentation

            nb_geom = 0
            for itemGeom in representation.Items :
                nb_geom += 1
                if(nb_geom > 300) :
                    continue
                indexListTemp = None
                vertexListTemp = None
                if(representation.RepresentationType == "Tessellation") :
                    indexListTemp = itemGeom.CoordIndex
                    vertexListTemp = itemGeom.Coordinates.CoordList
                elif(representation.RepresentationType == "SweptSolid") :
                    vertexListTemp,indexListTemp = self.extrudGeom(itemGeom)
                if(vertexListTemp and indexListTemp) :
                    for index in indexListTemp :
                        indexList.append([index[0]+len(vertexList),index[1]+len(vertexList),index[2]+len(vertexList)])
                    for vertex in vertexListTemp:
                        vertexList.append(np.array([vertex[0],vertex[1],vertex[2]],dtype=np.float32))


        if (len(indexList) == 0) :
            return False

        for j in range(len(vertexList)):
            vertex = vertexList[j]
            for i in range(len(listDirection)) :
                vertex = np.dot(np.array(vertex),listDirection[i])
                vertex = (vertex + listPosition[i])
            if(self.convertToMeter):
                vertex = vertex / 100
            vertexList[j] = np.array([round(vertex[0],5),round(vertex[1],5),round(vertex[2],5)],dtype=np.float32)

        triangles = list()
        for index in indexList:
            triangle = []
            for i in range(0,3): 
                # We store each position for each triangles, as GLTF expect
                triangle.append(vertexList[index[i] - 1])
            triangles.append(triangle)
        
        self.geom.triangles.append(triangles)

        self.set_box()

        return True
    
    def set_box(self):
        """
        Parameters
        ----------
        Returns
        -------
        """
        bbox = self.geom.getBbox()
        self.box = BoundingVolumeBox()
        self.box.set_from_mins_maxs(np.append(bbox[0],bbox[1]))
        
        # Set centroid from Bbox center
        self.centroid = np.array([(bbox[0][0] + bbox[1][0]) / 2.0,
                         (bbox[0][1] + bbox[1][1]) / 2.0,
                         (bbox[0][2] + bbox[0][2]) / 2.0])

    def get_obj_id(self):
        return super().get_id()
    
    def set_obj_id(self,id):
        return super().set_id(id)

class IfcObjectsGeom(ObjectsToTile):
    """
        A decorated list of ObjectsToTile type objects.
    """
    def __init__(self,objs=None):
        super().__init__(objs)

    # def translate_tileset(self,offset):
    #     """
    #     :param objects: an array containing objs 
    #     :param offset: an offset
    #     :return: 
    #     """
    #     # Translate the position of each obj by an offset
    #     for obj in self.objects:
    #         new_geom = []
    #         for triangle in obj.get_geom_as_triangles():
    #             new_position = []
    #             for points in triangle:
    #                 # Must to do this this way to ensure that the new position 
    #                 # stays in float32, which is mandatory for writing the GLTF
    #                 new_position.append(np.array(points - offset, dtype=np.float32))
    #             new_geom.append(new_position)
    #         obj.set_triangles(new_geom)
    #         obj.set_box() 
    
    @staticmethod
    def computeCentroid(ifcSite,convertToMeter) :
        elevation = ifcSite.RefElevation
        placement = ifcSite.ObjectPlacement.RelativePlacement
        location = placement.Location.Coordinates
        transformer = Transformer.from_crs("EPSG:27562", "EPSG:3946")
        if(convertToMeter) :
            location = (location[0]/100,location[1]/100,location[2] / 100)
        location = transformer.transform(location[0],location[1])
        direction = computeDirection(placement.Axis.DirectionRatios,placement.RefDirection.DirectionRatios)
        centroid = [direction[0][0],direction[0][1],direction[0][2],0,
                    direction[1][0],direction[1][1],direction[1][2],0,
                    direction[2][0],direction[2][1],direction[2][2],0,
                    location[0],location[1],elevation,1]
        return centroid


    @staticmethod
    def retrievObjByType(path_to_file,convertToMeter = False):
        """
        :param path: a path to a directory

        :return: a list of Obj. 
        """
        ifc_file = ifcopenshell.open(path_to_file)
        
        centroid = IfcObjectsGeom.computeCentroid(ifc_file.by_type('IfcSite')[0],convertToMeter)
        elements = ifc_file.by_type('IfcElement')   

        dictObjByType = dict()
        for element in elements:
            if not(element.is_a() in dictObjByType):
                print(element.is_a())
                dictObjByType[element.is_a()] = list()   

            obj = IfcObjectGeom(element,convertToMeter)
            if(obj.hasGeom()):
                dictObjByType[element.is_a()].append(obj)

        for key in dictObjByType.keys():
            dictObjByType[key] = IfcObjectsGeom(dictObjByType[key])

        return dictObjByType, centroid
   
