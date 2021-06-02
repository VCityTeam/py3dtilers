# -*- coding: utf-8 -*-

import json
import unittest
from py3dtiles import TemporalBatchTable, HelperTest
from tests.test_batch_table import Test_Batch


class Test_TemporalBatchTable(unittest.TestCase):
    """
    Batch Table extension of the Temporal applicative extension
    """
    def test_basics(self):
        helper = HelperTest(lambda x: TemporalBatchTable().validate(x))
        helper.sample_file_names.append(
                      'temporal_extension_batch_table_sample.json')
        if not helper.check():
            self.fail()

    def build_sample(self):
        """
        Programmatically define the reference a sample.
        :return: the sample as TemporalBatchTable object.
        """
        tbt = TemporalBatchTable()

        tbt.set_start_dates(["2018-01-01", "2028-02-02"])
        tbt.append_start_date("2038-03-03")
        tbt.set_end_dates(["2019-01-01", "2029-02-02"])
        tbt.append_end_date("2039-03-03")
        tbt.set_feature_ids(["1", "2"])
        tbt.append_feature_id("3")

        return tbt

    def test_json_encoding(self):
        return self.build_sample().to_json()

    def test_tbt_build_sample_and_validate(self):
        if not self.build_sample().validate():
            self.fail()

    def test_build_sample_and_compare_reference_file(self):
        """
        Build the sample, load the version from the reference file and
        compare them (in memory as opposed to "diffing" files)
        """
        json_tbt = json.loads(self.build_sample().to_json())
        json_tbt_reference = HelperTest().load_json_reference_file(
                            'temporal_extension_batch_table_sample.json')
        if not json_tbt.items() == json_tbt_reference.items():
            self.fail()

    def test_plug_extension_into_simple_batch_table(self):
        bt = Test_Batch.build_bt_sample()
        tbt = self.build_sample()
        bt.add_extension(tbt)
        bt.validate()

        # Voluntarily introduce a mistake in the added extension in order
        # to make sure that the extension is really validated. If bt.validate()
        # is still true then the validation didn't check the extension and
        # hence the test must fail.
        tbt.attributes['featureIds'].append(1)
        if bt.validate(quiet=True):
            self.fail()


if __name__ == "__main__":
    unittest.main()
