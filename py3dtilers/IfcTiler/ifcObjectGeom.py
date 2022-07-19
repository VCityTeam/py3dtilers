# -*- coding: utf-8 -*-
import logging
import time
import numpy as np
import ifcopenshell
import itertools
from py3dtiles import GlTFMaterial
from ..Common import Feature, FeatureList, TreeWithChildrenAndParent
from ifcopenshell import geom
from py3dtiles import BatchTableHierarchy



class IfcObjectGeom(Feature):
    def __init__(self, ifcObject, ifcGroup=None, with_BTH=False):
        super().__init__(ifcObject.GlobalId)
        self.ifcClass = ifcObject.is_a()
        self.material = None
        self.setBatchTableData(ifcObject, ifcGroup)
        self.has_geom = self.parse_geom(ifcObject)
        if(with_BTH):
            self.getParentsInIfc(ifcObject)

    def hasGeom(self):
        return self.has_geom

    def set_triangles(self, triangles):
        self.geom.triangles[0] = triangles

    def getParentsInIfc(self,ifcObject):
        self.parents = list()
        while(ifcObject):
            ifcParent = None
            if(hasattr(ifcObject,"ContainedInStructure")):
                ifcParent =  ifcObject.ContainedInStructure[0].RelatingStructure
            elif(hasattr(ifcObject,"Decomposes")):
                if(len(ifcObject.Decomposes) > 0):
                    ifcParent = ifcObject.Decomposes[0].RelatingObject

            if(ifcParent):    
                self.parents.append({'id': ifcParent.GlobalId,'ifcClass':ifcParent.is_a()})
            ifcObject = ifcParent

    def computeCenter(self, pointList):
        center = np.array([0.0, 0.0, 0.0])
        for point in pointList:
            center += np.array([point[0], point[1], 0])
        return center / len(pointList)

    def setBatchTableData(self, ifcObject, ifcGroup):
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
            'classe': self.ifcClass,
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

    @staticmethod
    def create_batch_table_extension(extension_name, ids, objects):
        if extension_name == "batch_table_hierarchy":
            resulting_bth = BatchTableHierarchy()
            hierarchy = TreeWithChildrenAndParent()
            parents = dict()

            for obj in objects:
                resulting_bth.add_class(obj.ifcClass,{'GUID'})
                if(obj.parents[0]):
                    hierarchy.addNodeToParent(obj.id,obj.parents[0]['id'])
                i = 0
                for parent in obj.parents:
                    hierarchy.addNodeToParent(obj.parents[i-1]['id'],obj.parents[i]['id'])
                    if parent['id'] not in parents :
                        parents[parent['id']] = parent
                        resulting_bth.add_class(parent['ifcClass'],{'GUID'})
                    i = i + 1


            objectPosition = {}
            for i, (obj) in enumerate(objects):
                objectPosition[obj.id] = i
            for i, (parent) in enumerate(parents):
                objectPosition[parent] = i + len(objects)
            
            for obj in objects:
                resulting_bth.add_class_instance(
                  obj.ifcClass,
                  { 
                    'GUID':obj.id
                  },
                  [objectPosition[id_parent] for id_parent in hierarchy.getParents(obj.id)]  
                )
            for parent in parents.items():
                resulting_bth.add_class_instance(
                  parent[1]["ifcClass"],
                  { 
                    'GUID':parent[1]["id"]
                  },
                  [objectPosition[id_parent] for id_parent in hierarchy.getParents(parent[1]["id"])]  
                )
            
            return resulting_bth


    @staticmethod
    def retrievObjByType(path_to_file,with_BTH):
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
            if(element.is_a('IfcWall')):
                obj = IfcObjectGeom(element,with_BTH = with_BTH)
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
