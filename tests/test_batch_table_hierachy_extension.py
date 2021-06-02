# -*- coding: utf-8 -*-

import json
import unittest
from py3dtiles import BatchTableHierarchy, HelperTest
from tests.test_batch_table import Test_Batch


class Test_BatchTableHierarchy(unittest.TestCase):
    """
    Batch Table Hierarchy (BTH) extension related tests
    """
    def test_basics(self):
        helper = HelperTest(lambda x: BatchTableHierarchy().validate(x))
        helper.sample_file_names.append(
                              'batch_table_hierarchy_reference_sample.json')
        if not helper.check():
            self.fail()

    def build_sample(self):
        """
        Programmatically define the reference sample encountered in the
        BTH specification cf
        https://github.com/AnalyticalGraphicsInc/3d-tiles/tree/master/extensions/3DTILES_batch_table_hierarchy#batch-table-json-schema-updates
        :return: the sample as BatchTableHierarchy object.
        """
        bth = BatchTableHierarchy()

        bth.add_class("Wall", ["color"])
        bth.add_class_instance("Wall", {'color': 'white'},  [6])
        bth.add_class_instance("Wall", {'color': 'red'},    [6, 10,11])
        bth.add_class_instance("Wall", {'color': 'yellow'}, [7, 11])
        bth.add_class_instance("Wall", {'color': 'gray'},   [7])
        bth.add_class_instance("Wall", {'color': 'brown'},  [8])
        bth.add_class_instance("Wall", {'color': 'black'},  [8])

        bth.add_class("Building", ["name", "address"])
        bth.add_class_instance("Building", {'name': 'unit29',
                                            'address': '100 Main St'}, [10])
        bth.add_class_instance("Building", {'name': 'unit20',
                                            'address': '102 Main St'}, [10])
        bth.add_class_instance("Building", {'name': 'unit93',
                                            'address': '104 Main St'}, [9])

        bth.add_class("Owner", ["type", "id"])
        bth.add_class_instance("Owner", {'type': 'city',       'id': 1120})
        bth.add_class_instance("Owner", {'type': 'resident',   'id': 1250})
        bth.add_class_instance("Owner", {'type': 'commercial', 'id': 6445})
        return bth

    def test_json_encoding(self):
        return self.build_sample().to_json()

    def test_bth_build_sample_and_validate(self):
        if not self.build_sample().validate():
            self.fail()

    def test_bth_build_sample_and_compare_reference_file(self):
        """
        Build the sample, load the version from the reference file and
        compare them (in memory as opposed to "diffing" files)
        """
        json_bth = json.loads(self.build_sample().to_json())
        json_bth_reference = HelperTest().load_json_reference_file(
                            'batch_table_hierarchy_reference_sample.json')
        if not json_bth.items() == json_bth_reference.items():
            self.fail()

    def test_plug_extension_into_simple_batch_table(self):
        bt = Test_Batch.build_bt_sample()
        bth = self.build_sample()
        bt.add_extension(bth)
        bt.validate()

        # Voluntarily introduce a mistake in the added extension in order
        # to make sure that the extension is really validated. If bt.validate()
        # is still true then the validation didn't check the extension and
        # hence the test must fail.
        bth.attributes['instancesLength'] = -1
        if bt.validate(quiet=True):
            self.fail()


if __name__ == "__main__":
    unittest.main()
