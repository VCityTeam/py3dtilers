# -*- coding: utf-8 -*-

import json
import unittest
from py3dtiles import TemporalTransaction, HelperTest


class Test_TemporalTransaction(unittest.TestCase):
    """
    Batch Table extension of the Temporal applicative extension
    """
    def test_basics(self):
        helper = HelperTest(lambda x: TemporalTransaction().validate(x))
        helper.sample_file_names.append(
                      'temporal_extension_transaction_sample.json')
        if not helper.check():
            self.fail()

    @classmethod
    def build_sample(cls):
        """
        Programmatically define the reference a sample.
        :return: the sample as TemporalBatchTable object.
        """
        tt = TemporalTransaction()

        tt.set_start_date("2018-01-01")
        tt.set_end_date("2019-01-01")
        tt.set_tags(["heightened"])
        tt.set_sources(["some-id"])
        tt.append_source("some-other-id")
        tt.set_destinations(["a given id"])
        tt.append_destination("another given id")

        return tt

    def test_json_encoding(self):
        return self.build_sample().to_json()

    def test_tt_build_sample_and_validate(self):
        if not self.build_sample().validate():
            self.fail()

    def test_build_sample_and_compare_reference_file(self):
        """
        Build the sample, load the version from the reference file and
        compare them (in memory as opposed to "diffing" files)
        """
        json_tt = json.loads(self.build_sample().to_json())
        json_tt_reference = HelperTest().load_json_reference_file(
                            'temporal_extension_transaction_sample.json')
        # We do not want to compare the identifiers (that must differ):
        del json_tt['id']
        del json_tt_reference['id']
        if not json_tt.items() == json_tt_reference.items():
            self.fail()


if __name__ == "__main__":
    unittest.main()
