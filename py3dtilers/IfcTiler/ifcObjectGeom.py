# -*- coding: utf-8 -*-
import sys
import logging
import math
import time
import numpy as np
import ifcopenshell
from py3dtiles import GlTFMaterial
from ..Common import Feature, FeatureList
from ifcopenshell import geom


def unitConversion(originalUnit, targetedUnit):
    conversions = {
        "mm": {"mm": 1, "cm": 1 / 10, "m": 1 / 1000, "km": 1 / 1000000},
        "cm": {"mm": 10, "cm": 1, "m": 1 / 100, "km": 1 / 100000},
        "m": {"mm": 1000, "cm": 100, "m": 1, "km": 1 / 1000},
        "km": {"mm": 100000, "cm": 10000, "m": 1000, "km": 1},
    }
    return conversions[originalUnit][targetedUnit]


class IfcObjectGeom(Feature):
    def __init__(self, ifcObject, originalUnit="m", targetedUnit="m", ifcGroup=None):
        super().__init__(ifcObject.GlobalId)

        self.ifcObject = ifcObject
        self.setIfcClasse(ifcObject.is_a(), ifcGroup)
        self.convertionRatio = unitConversion(originalUnit, targetedUnit)
        # self.material = None
        self.has_geom = self.parse_geom()

    def hasGeom(self):
        return self.has_geom

    def get_geom_as_triangles(self):
        return self.geom.triangles[0]

    def set_triangles(self, triangles):
        self.geom.triangles[0] = triangles

    def computeCenter(self, pointList):
        center = np.array([0.0, 0.0, 0.0])
        for point in pointList:
            center += np.array([point[0], point[1], 0])
        return center / len(pointList)

    def setIfcClasse(self, ifcClasse, ifcGroup):
        self.ifcClasse = ifcClasse
        properties = list()
        for prop in self.ifcObject.IsDefinedBy:
            if(hasattr(prop,'RelatingPropertyDefinition')):
                if(prop.RelatingPropertyDefinition.is_a('IfcPropertySet')):
                    props = list()
                    props.append(prop.RelatingPropertyDefinition.Name)
                    for propSet in prop.RelatingPropertyDefinition.HasProperties :
                        if(propSet.is_a('IfcPropertySingleValue')):
                            if(propSet.NominalValue):
                                props.append([propSet.Name,propSet.NominalValue.wrappedValue])
                    properties.append(props)
        batch_table_data = {
            'classe': ifcClasse,
            'group': ifcGroup,
            'name': self.ifcObject.Name,
            'properties' : properties
        }
        super().set_batchtable_data(batch_table_data)

    def getIfcClasse(self):
        return self.ifcClasse

    def parse_geom(self):
        if (not(self.ifcObject.Representation)):
            return False

        try :
            settings = geom.settings()
            settings.set(settings.USE_WORLD_COORDS, True) #Translates and rotates the points to their world coordinates
            settings.set(settings.SEW_SHELLS,True)
            shape = geom.create_shape(settings,self.ifcObject)
        except RuntimeError:
            logging.error("Error while creating geom with IfcOpenShell")
            return False

        vertexList = np.reshape(np.array(shape.geometry.verts),(-1,3))
        indexList = np.reshape(np.array(shape.geometry.faces),(-1,3))
        if(shape.geometry.materials):
            ifc_material = shape.geometry.materials[0]
            self.material = GlTFMaterial(rgb=[ifc_material.diffuse[0],ifc_material.diffuse[1],ifc_material.diffuse[2],ifc_material.transparency],
                        alpha= ifc_material.transparency if ifc_material.transparency else 0,
                        metallicFactor= ifc_material.specularity if ifc_material.specularity else 1.)    


        triangles = list()
        for index in indexList:
            triangle = []
            for i in range(0, 3):
                # We store each position for each triangles, as GLTF expect
                triangle.append(vertexList[index[i]])
            triangles.append(triangle)

        self.geom.triangles.append(triangles)

        self.set_box()

        return True

    def get_obj_id(self):
        return super().get_id()

    def set_obj_id(self, id):
        return super().set_id(id)


class IfcObjectsGeom(FeatureList):
    """
        A decorated list of FeatureList type objects.
    """

    def __init__(self, objs=None):
        super().__init__(objs)

    @staticmethod
    def retrievObjByType(path_to_file, originalUnit="m", targetedUnit="m"):
        """
        :param path: a path to a directory

        :return: a list of Obj.
        """
        ifc_file = ifcopenshell.open(path_to_file)

        elements = ifc_file.by_type('IfcElement')
        nb_element = str(len(elements))
        logging.info(nb_element + " elements to parse")
        i = 1
        dictObjByType = dict()
        for element in elements:
            start_time = time.time()
            logging.info(str(i) + " / " + nb_element)
            logging.info("Parsing "+element.GlobalId+", "+element.is_a())
            obj = IfcObjectGeom(element, originalUnit, targetedUnit)
            if(obj.hasGeom()):
                if not(element.is_a() in dictObjByType):
                    dictObjByType[element.is_a()] = IfcObjectsGeom()
                # if(obj.material):
                #     obj.material_index = dictObjByType[element.is_a()].get_material_index(obj.material)
                dictObjByType[element.is_a()].append(obj)
            logging.info("--- %s seconds ---" % (time.time() - start_time))            
            i = i + 1
        return dictObjByType

    def is_material_registered(self,material):
        for mat in self.materials:
            if(mat.rgba == material.rgba).all():
                return True
        return False
    
    def get_material_index(self,material):
        i=0
        for mat in self.materials:
            if(mat.rgba == material.rgba).all():
                return i
            i = i+1
        self.add_material(material)
        return i
    @staticmethod
    def retrievObjByGroup(path_to_file, originalUnit="m", targetedUnit="m"):
        """
        :param path: a path to a directory

        :return: a list of Obj.
        """
        ifc_file = ifcopenshell.open(path_to_file)
        
        elements = ifc_file.by_type('IfcElement')
        nb_element = str(len(elements))
        logging.info(nb_element + " elements to parse")

        groups = ifc_file.by_type("IFCRELASSIGNSTOGROUP")

        dictObjByGroup = dict()
        for group in groups:
            elements_in_group = list()
            for element in group.RelatedObjects:
                if(element.is_a('IfcElement')):
                    elements.remove(element)
                    obj = IfcObjectGeom(element, originalUnit, targetedUnit, group.RelatingGroup.Name)
                    if(obj.hasGeom()):
                        elements_in_group.append(obj)
            dictObjByGroup[group.RelatingGroup.Name] = elements_in_group

        elements_not_in_group = list()
        for element in elements:
            obj = IfcObjectGeom(element, originalUnit, targetedUnit)
            if(obj.hasGeom()):
                elements_not_in_group.append(obj)
        dictObjByGroup["None"] = elements_not_in_group

        for key in dictObjByGroup.keys():
            dictObjByGroup[key] = IfcObjectsGeom(dictObjByGroup[key])

        return dictObjByGroup
