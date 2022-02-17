# -*- coding: utf-8 -*-
import logging
import time
import numpy as np
import ifcopenshell
from py3dtiles import GlTFMaterial
from ..Common import Feature, FeatureList, TreeWithChildrenAndParent
from ifcopenshell import geom
from py3dtiles import BatchTableHierarchy


class IfcObjectGeom(Feature):
    def __init__(self, ifcObject, originalUnit="m", targetedUnit="m", ifcGroup=None):
        super().__init__(ifcObject.GlobalId)
        self.setIfcClasse(ifcObject, ifcGroup)
        self.material = None
        self.has_geom = self.parse_geom(ifcObject)

    def hasGeom(self):
        return self.has_geom

    def set_triangles(self, triangles):
        self.geom.triangles[0] = triangles

    def get_parents(self):

        if(self.ifcObject.ContainedInStructure):
            print("parent")



    def computeCenter(self, pointList):
        center = np.array([0.0, 0.0, 0.0])
        for point in pointList:
            center += np.array([point[0], point[1], 0])
        return center / len(pointList)

    def setIfcClasse(self, ifcObject, ifcGroup):
        self.ifcClasse = ifcObject.is_a()
        properties = list()
        for prop in ifcObject.IsDefinedBy:
            if(hasattr(prop, 'RelatingPropertyDefinition')):
                if(prop.RelatingPropertyDefinition.is_a('IfcPropertySet')):
                    props = list()
                    props.append(prop.RelatingPropertyDefinition.Name)
                    for propSet in prop.RelatingPropertyDefinition.HasProperties:
                        if(propSet.is_a('IfcPropertySingleValue')):
                            if(propSet.NominalValue):
                                props.append([propSet.Name, propSet.NominalValue.wrappedValue])
                    properties.append(props)
        batch_table_data = {
            'classe': self.ifcClasse,
            'group': ifcGroup,
            'name': ifcObject.Name,
            'properties': properties
        }
        super().set_batchtable_data(batch_table_data)

    def getIfcClasse(self):
        return self.ifcClasse

    def parse_geom(self, ifcObject):
        if (not(ifcObject.Representation)):
            return False

        try:
            settings = geom.settings()
            settings.set(settings.USE_WORLD_COORDS, True)  # Translates and rotates the points to their world coordinates
            settings.set(settings.SEW_SHELLS, True)
            settings.set(settings.APPLY_DEFAULT_MATERIALS, False)
            shape = geom.create_shape(settings, ifcObject)
        except RuntimeError:
            logging.error("Error while creating geom with IfcOpenShell")
            return False

        vertexList = np.reshape(np.array(shape.geometry.verts), (-1, 3))
        indexList = np.reshape(np.array(shape.geometry.faces), (-1, 3))
        if(shape.geometry.materials):
            ifc_material = shape.geometry.materials[0]
            self.material = GlTFMaterial(rgb=[ifc_material.diffuse[0], ifc_material.diffuse[1], ifc_material.diffuse[2]],
                                         alpha=ifc_material.transparency if ifc_material.transparency else 0,
                                         metallicFactor=ifc_material.specularity if ifc_material.specularity else 1.)

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

    def create_batch_table_extension(extension_name, ids, objects):
        resulting_bth = BatchTableHierarchy()
        hierarchy = TreeWithChildrenAndParent()
        classDict = {}

        for obj in objects:
            obj.get_parents(hierarchy,classDict)
        
        print(ids)


    @staticmethod
    def retrievObjByType(path_to_file):
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
            logging.info("Parsing " + element.GlobalId + ", " + element.is_a())
            obj = IfcObjectGeom(element)
            if(obj.hasGeom()):
                if not(element.is_a() in dictObjByType):
                    dictObjByType[element.is_a()] = IfcObjectsGeom()
                if(obj.material):
                    obj.material_index = dictObjByType[element.is_a()].get_material_index(obj.material)
                else:
                    obj.material_index = 0
                dictObjByType[element.is_a()].append(obj)
            logging.info("--- %s seconds ---" % (time.time() - start_time))
            i = i + 1
        return dictObjByType

    @staticmethod
    def retrievObjByGroup(path_to_file):
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
                    obj = IfcObjectGeom(element, group.RelatingGroup.Name)
                    if(obj.hasGeom()):
                        elements_in_group.append(obj)
            dictObjByGroup[group.RelatingGroup.Name] = elements_in_group

        elements_not_in_group = list()
        for element in elements:
            obj = IfcObjectGeom(element)
            if(obj.hasGeom()):
                elements_not_in_group.append(obj)
        dictObjByGroup["None"] = elements_not_in_group

        for key in dictObjByGroup.keys():
            dictObjByGroup[key] = IfcObjectsGeom(dictObjByGroup[key])

        return dictObjByGroup
