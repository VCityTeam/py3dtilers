# -*- coding: utf-8 -*-
from .extension import Extension
from .threedtiles_notion import ThreeDTilesNotion


class BatchTableHierarchy(Extension, ThreeDTilesNotion):
    """
    Batch Table Hierarchy (BAH) is an Extension of a Batch Table.
    """

    def __init__(self):
        Extension.__init__(self, '3DTILES_batch_table_hierarchy')
        ThreeDTilesNotion.__init__(self)

        '''
        List of the _indexes_ of the class (types) used by this BTH.
        '''
        self._class_to_index = {}

        self.attributes['classes'] = list()
        self.attributes['instancesLength'] = 0
        self.attributes['classIds'] = list()
        self.attributes['parentCounts'] = list()
        self.attributes['parentIds'] = list()

    def add_class(self, class_name, property_names):
        """
        :param class_name: the name of the class (as a type) to be defined
        :param property_names: array of strings holding the names of the
                              properties (attributes) defining this class
        :return: None
        """
        self.attributes['classes'].append({
            'name': class_name,
            'length': 0,
            'instances': {property_name: []
                          for property_name in property_names}})
        self._class_to_index[class_name] = len(self._class_to_index)

    # properties: dictionary with the same attributes as class instances
    # parent indices refers to the index of the parent in the batch table
    def add_class_instance(self, class_name, properties, parent_indexes = []):
        """
        :param class_name: a class name of class (type) previously
                           defined with the add_class() method
        :param properties: dictionary with the same attributes as defined
                           in the class type (referred by class_name)
        :param parent_indexes: indexes of the parent(s)
        """
        index = self._class_to_index[class_name]
        my_class = self.attributes['classes'][index]
        my_class['length'] += 1
        for property in my_class['instances']:
            my_class['instances'][property].append(properties[property])
        self.attributes['instancesLength'] += 1
        self.attributes['classIds'].append(index)
        self.attributes['parentCounts'].append(len(parent_indexes))
        self.attributes['parentIds'].extend(parent_indexes)

