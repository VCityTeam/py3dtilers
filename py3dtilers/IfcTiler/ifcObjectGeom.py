# -*- coding: utf-8 -*-
import logging
import time
import numpy as np
import ifcopenshell
from py3dtiles import GlTFMaterial
from ..Common import Feature, FeatureList, TreeWithChildrenAndParent
from ifcopenshell import geom
from py3dtiles import BatchTableHierarchy
import ifcopenshell.util.element


class IfcObjectGeom(Feature):
    def __init__(self, ifcObject, ifcGroup="None", ifcSpace="None", with_BTH=False):
        super().__init__(ifcObject.GlobalId)
        self.ifcClass = ifcObject.is_a()
        self.material = None
        self.ifcGroup = ifcGroup
        self.ifcSpace = ifcSpace
        self.setBatchTableData(ifcObject, ifcGroup, ifcSpace)
        self.has_geom = self.parse_geom(ifcObject)
        if with_BTH:
            self.getParentsInIfc(ifcObject)

    def hasGeom(self):
        return self.has_geom

    def set_triangles(self, triangles):
        self.geom.triangles[0] = triangles

    def getParentsInIfc(self, ifcObject):
        self.parents = list()
        while ifcObject:
            ifcParent = ifcopenshell.util.element.get_container(ifcObject)

            if not ifcParent:
                if hasattr(ifcObject, "Decomposes"):
                    if len(ifcObject.Decomposes) > 0:
                        ifcParent = ifcObject.Decomposes[0].RelatingObject
                if hasattr(ifcObject, "VoidsElements"):
                    if len(ifcObject.VoidsElements) > 0:
                        ifcParent = ifcObject.VoidsElements[0].RelatingBuildingElement
            if ifcParent:
                self.parents.append({'id': ifcParent.GlobalId, 'ifcClass': ifcParent.is_a()})
            ifcObject = ifcParent

    def computeCenter(self, pointList):
        center = np.array([0.0, 0.0, 0.0])
        for point in pointList:
            center += np.array([point[0], point[1], 0])
        return center / len(pointList)

    def setBatchTableData(self, ifcObject, ifcGroup, ifcSpace):
        properties = list()
        for prop in ifcObject.IsDefinedBy:
            if hasattr(prop, 'RelatingPropertyDefinition'):
                if prop.RelatingPropertyDefinition.is_a('IfcPropertySet'):
                    props = list()
                    props.append(prop.RelatingPropertyDefinition.Name)
                    for propSet in prop.RelatingPropertyDefinition.HasProperties:
                        if propSet.is_a('IfcPropertySingleValue'):
                            if propSet.NominalValue:
                                props.append([propSet.Name, propSet.NominalValue.wrappedValue])
                    properties.append(props)
        batch_table_data = {
            'classe': self.ifcClass,
            'group': ifcGroup,
            'space': ifcSpace,
            'name': ifcObject.Name,
            'properties': properties
        }
        super().set_batchtable_data(batch_table_data)

    def getIfcClasse(self):
        return self.ifcClasse

    def parse_geom(self, ifcObject):
        if not (ifcObject.Representation):
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
        if shape.geometry.materials:
            ifc_material = shape.geometry.materials[0]
            self.material = GlTFMaterial(rgb=[ifc_material.diffuse[0], ifc_material.diffuse[1], ifc_material.diffuse[2]])

        if indexList.size == 0:
            logging.error("Error while creating geom : No triangles found")
            return False

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
                if not any(d.get('name') == obj.ifcClass for d in resulting_bth.attributes['classes']):
                    resulting_bth.add_class(obj.ifcClass, {'GUID'})
                if obj.parents:
                    hierarchy.addNodeToParent(obj.id, obj.parents[0]['id'])
                i = 1
                for parent in obj.parents:
                    if i < len(obj.parents):
                        hierarchy.addNodeToParent(obj.parents[i - 1]['id'], obj.parents[i]['id'])
                    if parent['id'] not in parents:
                        parents[parent['id']] = parent
                    if not any(d.get('name') == parent['ifcClass'] for d in resulting_bth.attributes['classes']):
                        resulting_bth.add_class(parent['ifcClass'], {'GUID'})
                    i += 1

            objectPosition = {}
            for i, obj in enumerate(objects):
                objectPosition[obj.id] = i
            for i, parent in enumerate(parents):
                objectPosition[parent] = i + len(objects)

            for obj in objects:
                resulting_bth.add_class_instance(
                    obj.ifcClass,
                    {
                        'GUID': obj.id
                    },
                    [objectPosition[id_parent] for id_parent in hierarchy.getParents(obj.id)]
                )
            for parent in parents.items():
                resulting_bth.add_class_instance(
                    parent[1]["ifcClass"],
                    {
                        'GUID': parent[1]["id"]
                    },
                    [objectPosition[id_parent] for id_parent in hierarchy.getParents(parent[1]["id"])]
                )

            return resulting_bth
        else:
            return None

    @staticmethod
    def retrievObjByType(path_to_file, with_BTH):
        """
        :param path: a path to a directory

        :return: a list of Obj.
        """
        ifc_file = ifcopenshell.open(path_to_file)

        buildings = ifc_file.by_type('IfcBuilding')
        dictObjByType = dict()
        _ = ifc_file.by_type('IfcSlab')
        i = 1

        for building in buildings:
            elements = ifcopenshell.util.element.get_decomposition(building)
            nb_element = str(len(elements))
            logging.info(nb_element + " elements to parse in building :" + building.GlobalId)
            for element in elements:
                start_time = time.time()
                logging.info(str(i) + " / " + nb_element)
                logging.info("Parsing " + element.GlobalId + ", " + element.is_a())
                obj = IfcObjectGeom(element, with_BTH=with_BTH)
                if obj.hasGeom():
                    if not (element.is_a() + building.GlobalId in dictObjByType):
                        dictObjByType[element.is_a() + building.GlobalId] = IfcObjectsGeom()
                    if obj.material:
                        obj.material_index = dictObjByType[element.is_a() + building.GlobalId].get_material_index(obj.material)
                    else:
                        obj.material_index = 0
                    dictObjByType[element.is_a() + building.GlobalId].append(obj)
                logging.info("--- %s seconds ---" % (time.time() - start_time))
                i = i + 1
        return dictObjByType

    @staticmethod
    def retrievObjByGroup(path_to_file, with_BTH):
        """
        :param path: a path to a directory

        :return: a list of Obj.
        """
        ifc_file = ifcopenshell.open(path_to_file)

        elements = ifc_file.by_type('IfcElement')
        nb_element = str(len(elements))
        logging.info(nb_element + " elements to parse")

        groups = ifc_file.by_type("IFCRELASSIGNSTOGROUP")
        if not groups:
            logging.info("No IfcGroup found")

        dictObjByGroup = dict()
        for group in groups:
            dictObjByGroup[group.RelatingGroup.Name] = IfcObjectsGeom()
            for element in group.RelatedObjects:
                if element.is_a('IfcElement'):
                    logging.info("Parsing " + element.GlobalId + ", " + element.is_a())
                    elements.remove(element)
                    obj = IfcObjectGeom(element, ifcGroup=group.RelatingGroup.Name, with_BTH=with_BTH)
                    if obj.hasGeom():
                        dictObjByGroup[element.ifcGroup].append(obj)
                    if obj.material:
                        obj.material_index = dictObjByGroup[element.ifcGroup].get_material_index(obj.material)
                    else:
                        obj.material_index = 0

        dictObjByGroup["None"] = IfcObjectsGeom()
        for element in elements:
            logging.info("Parsing " + element.GlobalId + ", " + element.is_a())
            obj = IfcObjectGeom(element, with_BTH=with_BTH)
            if obj.hasGeom():
                dictObjByGroup[obj.ifcGroup].append(obj)
            if obj.material:
                obj.material_index = dictObjByGroup[obj.ifcGroup].get_material_index(obj.material)
            else:
                obj.material_index = 0

        return dictObjByGroup

    @staticmethod
    def retrievObjBySpace(path_to_file, with_BTH):
        """
        :param path: a path to an ifc
        :return: a list of obj grouped by IfcSpace
        """
        ifc_file = ifcopenshell.open(path_to_file)

        elements = ifc_file.by_type('IfcElement')
        nb_element = str(len(elements))
        logging.info(nb_element + " elements to parse")

        dictObjByIfcSpace = dict()
        # init a group for objects not in any IfcSpace
        dictObjByIfcSpace["None"] = IfcObjectsGeom()
        ifc_spaces = ifc_file.by_type("IFCSPACE")
        logging.info(f"Found {len(ifc_spaces)} IfcSpace.")

        # init a group for each IfcSpace
        for s in ifc_spaces:
            dictObjByIfcSpace[s.id()] = IfcObjectsGeom()
            obj = IfcObjectGeom(s, with_BTH=with_BTH)
            if obj.hasGeom():
                # we put the ifcspace as any other geom in its tile
                dictObjByIfcSpace[s.id()].append(obj)
                if obj.material:
                    obj.material_index = dictObjByIfcSpace[s.id()].get_material_index(obj.material)
            else:
                obj.material_index = 0

        # Iterate over all elements, and attribute them to spaces when we can
        for e in elements:
            container = ifcopenshell.util.element.get_container(e)
            if container is None or container.is_a() != 'IfcSpace':
                ifcspace_id_key = 'None'
            else:
                ifcspace_id_key = container.id()
            obj = IfcObjectGeom(e, with_BTH=with_BTH, ifcSpace=ifcspace_id_key)
            if obj.hasGeom():
                group = dictObjByIfcSpace[ifcspace_id_key]
                group.append(obj)
                if obj.material:
                    obj.material_index = group.get_material_index(obj.material)
            else:
                obj.material_index = 0
        return dictObjByIfcSpace
