# -*- coding: utf-8 -*-

import json
import unittest
from py3dtiles import BatchTable, HelperTest


class Test_Batch(unittest.TestCase):

    def test_basics(self):
        helper = HelperTest(lambda x: BatchTable().validate(x))
        helper.sample_file_names.append('batch_table_sample.json')
        if not helper.check():
            self.fail()

    @classmethod
    def build_bt_sample(cls):
        """
        Programmatically define the reference sample encountered in the
        Bath Table specification cf
        https://github.com/AnalyticalGraphicsInc/3d-tiles/blob/master/specification/TileFormats/BatchTable/README.md#json-header
        :return: the sample as BatchTable object.
        """
        bt = BatchTable()

        bt.add_property_from_array("id",
                                   ["unique id", "another unique id"])
        bt.add_property_from_array("displayName",
                                   ["Building name", "Another building name"])
        bt.add_property_from_array("yearBuilt",
                                   [1999, 2015])
        bt.add_property_from_array("address",
                            [{"street" : "Main Street", "houseNumber" : "1"},
                             {"street" : "Main Street", "houseNumber" : "2"}])
        return bt

    def test_json_encoding(self):
        return self.build_bt_sample().to_json()

    def test_bt_build_sample_and_validate(self):
        """
        Assert the build sample is valid against the BTH extension definition
        """
        if not self.build_bt_sample().validate():
            print('json_bt is not valid against the schema')
            self.fail()

    def test_bt_build_sample_and_compare_reference_file(self):
        """
        Build the sample, load the version from the reference file and
        compare them (in memory as opposed to "diffing" files)
        """
        json_bt = json.loads(self.build_bt_sample().to_json())
        json_reference = HelperTest().load_json_reference_file(
                                                   'batch_table_sample.json')
        if not json_bt.items() == json_reference.items():
            self.fail()

if __name__ == "__main__":
    unittest.main()