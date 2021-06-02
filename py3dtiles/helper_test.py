# -*- coding: utf-8 -*-
import os
import json


class HelperTest:
    def __init__(self, validator=None):
        self.sample_file_names = list()
        self.validator = validator

    def load_json_reference_file(self, filename):
        try:
            reference_file_path = os.path.join('tests/data', filename)
            with open(reference_file_path, 'r') as reference_file:
                json_reference = json.loads(reference_file.read())
            json_reference.pop('_comment', None)  # Drop the "comment".
        except:
            print(f'Unable to parse reference file {reference_file_path}')
            return None
        return json_reference

    def test_load_reference_files(self):
        for file_name in self.sample_file_names:
            if not self.load_json_reference_file(file_name):
                return False
        return True

    def test_validate_reference_files(self):
        if not self.validator:
            print('Unset validator (was missing in constructor?)')
            return False
        for file_name in self.sample_file_names:
            json_reference = self.load_json_reference_file(file_name)
            if not self.validator(json_reference):
                return False
        return True

    def check(self):
        if not self.test_load_reference_files():
            return False
        if not self.test_validate_reference_files():
            return False
        return True