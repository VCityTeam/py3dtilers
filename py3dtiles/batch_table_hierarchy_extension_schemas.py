# -*- coding: utf-8 -*-
from .schema_with_sample import SchemaWithSample


class BatchTableHierarchySchemaWithSample(SchemaWithSample):

    def __init__(self):
        super().__init__('BatchTableHierarchy')
        self.set_directory('py3dtiles/jsonschemas')
        self.set_filename('3DTILES_batch_table_hierarchy.json')
        self.set_sample(
            {
                "classes": [],
                "instancesLength": 0,
                "classIds": [],
                "parentCounts": [],
                "parentIds": []
            }
        )


class BatchTableHierarchySchemas(list):
    def __init__(self, *args):
        list.__init__(self, *args)
        self.append(BatchTableHierarchySchemaWithSample())
