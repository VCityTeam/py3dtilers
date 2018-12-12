# -*- coding: utf-8 -*-
import sys
import json
import numpy
from py3dtiles import Extension, SchemaValidators, Tile


class ThreeDTilesNotion(object):
    """
    One the 3DTiles notions defined as an abstract data model through 
    a schema of the 3DTiles specifications (either core of extensions).
    """
    validators = None

    def __init__(self):
        if not ThreeDTilesNotion.validators:
            ThreeDTilesNotion.validators = SchemaValidators()
        self.header = dict()

    def add_property_from_array(self, property_name, array):
        self.header[property_name] = array

    def prepare_for_json(self):
        return

    def add_extension(self, extension):
        if not isinstance(extension, Extension):
            print(f'{extension} instance is not of type Extension')
            sys.exit(1)
        if 'extensions' not in self.header:
            self.header['extensions'] = dict()
        self.header['extensions'][extension.get_extension_name()] = extension

    def has_extensions(self):
        return 'extensions' in self.header

    def validate(self, item=None, *, quiet=False):
        """
        Validate the item (python object) against the json schema associated
        with the derived concrete class of ThreeDTilesNotion.
        :param item: a Python object e.g. either deserialized (typically
                     through a json.loads()) or build programmatically.
        :param quiet: silence console message when True
        :return: validate is a predicate
        """
        if not item:
            item = json.loads(self.to_json())
        class_name_key = self.__class__.__name__
        validator = self.validators.get_validator(class_name_key)
        try:
            validator.validate(item)
        except:
            if quiet:
                print(f'Invalid item for schema {class_name_key}')
            return False
        if self.has_extensions():
            for extension in self.header['extensions'].values():
                if not extension.validate():
                    return False
        return True

    def to_json(self):
        class JSONEncoder(json.JSONEncoder):

            def default(self, obj):
                if isinstance(obj, ThreeDTilesNotion):
                    obj.prepare_for_json()
                    return obj.header
                if isinstance(obj, Tile):
                    return "Tiles are in fact tile contents!!!"
                # Numpy arrays entries require an ad hoc treatment
                if isinstance(obj, numpy.ndarray):
                    return obj.tolist()
                # Let the base class default method raise the TypeError
                return json.JSONEncoder.default(self, obj)

        self.prepare_for_json()
        result = json.dumps(self.header,
                            separators=(',', ':'),
                            cls=JSONEncoder)
        return result

    def to_array(self):
        """
        :return: the notion encoded as an array of binaries
        """
        # First encode the header as a json string
        as_json = self.to_json()
        # and make sure it respects a mandatory 4-byte alignement (refer e.g.
        # to batch table documentation)
        as_json += ' '*(4 - len(as_json) % 4)
        # eventually return an array of binaries representing the
        # considered ThreeDTilesNotion
        return numpy.fromstring(as_json, dtype=numpy.uint8)