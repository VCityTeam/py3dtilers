# -*- coding: utf-8 -*-
import os
import sys
import json
import jsonschema


class SchemaValidators:
    """
    Dictionary holding the set of validated schemas. The dictionary key is
    the name of the schema as encountered in the "title" property of the schema.
    """
    schemas = None
    """
    Dictionary with the class_names (i.e. the name of the classes inheriting
    from ThreeDTilesNotion) as key and the "title" property of the associated
    schema as value. class_names can be seen as (technical) syntactic sugar
    over the true schema identifier that is the "title".
    """
    class_names = None
    """
    Resolver is a technical mean for retrieving any possible sub-schema 
    indicated within a given schema through a $ref entry.
    """
    resolver = None

    def __init__(self):
        if not self.schemas:
            self.schemas = dict()
            self.class_names = dict()

            # The directory (with a path relative to the module) where all
            # the schema files are located:
            relative_dir = 'py3dtiles/jsonschemas'

            # sub-schemas within the same directory (provided as absolute path)
            # as the given schema. Refer to
            #     https://github.com/Julian/jsonschema/issues/98
            # for the reasons of the following parameters and call
            base_uri = 'file://' + os.path.abspath(relative_dir) + '/'
            self.resolver = jsonschema.RefResolver(base_uri, None)

            for key, schema_file_name in {
                'BatchTable':          'batchTable.schema.json',
                'BatchTableHierarchy': '3DTILES_batch_table_hierarchy.json',
                'BoundingVolumeBox':   'boundingVolume.schema.json',
                'BoundingVolumeRegion':'boundingVolume.schema.json',
                'BoundingVolumeSphere':'boundingVolume.schema.json',
                'TileForReal':         'tile.schema.json',
                'TileSet':             'tileset.schema.json'
                }.items():
                schema_path_name = os.path.join('py3dtiles/jsonschemas',
                                                schema_file_name)
                self.append_schema_from_file(key, schema_path_name)

    def get_dummy_item(self, title):
        """
        Retrieve a dummy (as simple as possible to validate) json item
        corresponding to the title
        :param title: the title (i.e. the header name "title" within the
                      schema) of the designated schema.
        :return: the constructed dummy json item
        """
        if title == "3DTILES_batch_table_hierarchy extension":
            return \
            {
                "classes" : [],
                "instancesLength" : 0,
                "classIds" : [],
                "parentCounts" : [],
                "parentIds" : []
            }

        if title == "Batch Table":
            return \
            {
                "ids":[1, 2]
            }

        if title == "Bounding Volume":
            return \
            {
                "box": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
            }

        if title == "Tile":
            return \
            {
                "geometricError": 3.14159,
                "boundingVolume": {
                    "box": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
                }
            }
        if title == "Tileset":
            return \
                {
                    "asset": {"version": "1.0"},
                    "geometricError": 3.14159,
                    "root": {
                        "boundingVolume": {
                            "box": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
                        },
                        "geometricError": 3.14159
                    }
                }

        return None

    def append_schema_from_file(self, key, file_name):
        """
        Register an extension
        :param key: the name of the class (implementing ThreeDTilesNotion)
               to be used as access key to retrieve the associated validator.
        :param file_name: file holding the schema to be added to the
               the list of already registered schemas
               Warning: when the schema uses references ($ref entries) to
               other external schemas, those schema must be encountered in the
               SAME directory as the scheme itself (otherwise the schema
               reference resolver has no clue on where to find the sub-schemas)
        :return: None
        """
        if not os.path.isfile(file_name):
            print(f'No such file as {file_name}')
            sys.exit(1)

        try:
            with open(file_name, 'r') as schema_file:
                schema = json.loads(schema_file.read())
        except:
            print(f'Unable to parse schema held in {file_name}')
            sys.exit(1)

        try:
            title = schema['title']
        except:
            print('Schema argument misses a title. Dropping extension.')
            sys.exit(1)

        if title in self.schemas:
            if not key in 'BoundingVolume':
                # This is a legitimate case where some classes share the same validator
                pass
            else:
                print(f'Class {key} already has schema named {title}.')
                sys.exit(1)
        else:
            validator = jsonschema.Draft4Validator(schema, resolver = self.resolver)

            try:
                # In order to validate the schema itself we still need to
                # provide a dummy json item
                dummy_item = self.get_dummy_item(title)
                validator.validate(dummy_item)
            except jsonschema.exceptions.SchemaError:
                print(f'Invalid schema {title}')
                sys.exit(1)
            self.schemas[title] = {'schema': schema, 'validator': validator}
        self.class_names[key] = title

    def get_validator(self, class_name_key):
        if not class_name_key in self.class_names:
            print(f'Unregistered schema (class) key {class_name_key}')
            return None
        title = self.class_names[class_name_key]
        if not title in self.schemas:
            print(f'Unregistered schema with title {title}')
            return None
        try:
            return self.schemas[title]["validator"]
        except:
            print(f'Cannot find validator for schema {class_name_key}')
        return None

    def __contains__(self, schema_name):
        if schema_name in self.schemas:
            return True
        return False
