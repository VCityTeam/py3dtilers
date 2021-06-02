# -*- coding: utf-8 -*-

import json
import unittest
from py3dtiles import TemporalVersionTransition, HelperTest


class Test_TemporalVersionTransition(unittest.TestCase):
    """
    Batch Table extension of the Temporal applicative extension
    """
    def test_basics(self):
        helper = HelperTest(lambda x: TemporalVersionTransition().validate(x))
        helper.sample_file_names.append(
                      'temporal_extension_version_transition_sample.json')
        if not helper.check():
            self.fail()

    @classmethod
    def build_sample(cls):
        """
        Programmatically define the reference a sample.
        :return: the sample as TemporalBatchTable object.
        """
        tvt = TemporalVersionTransition()

        tvt.set_name("Version Transition Name")
        tvt.set_start_date("2018-01-01")
        tvt.set_end_date("2019-01-01")
        tvt.set_from(100)
        tvt.set_to(200)
        tvt.set_reason("Reason of evolution between two versions")
        tvt.set_type("merge")
        tvt.set_transactions([1000])
        tvt.append_transaction(2000)

        return tvt

    def test_json_encoding(self):
        return self.build_sample().to_json()

    def test_tvt_build_sample_and_validate(self):
        if not self.build_sample().validate():
            self.fail()

    def test_build_sample_and_compare_reference_file(self):
        """
        Build the sample, load the version from the reference file and
        compare them (in memory as opposed to "diffing" files)
        """
        json_tvt = json.loads(self.build_sample().to_json())
        json_tvt_reference = HelperTest().load_json_reference_file(
                            'temporal_extension_version_transition_sample.json')
        if not json_tvt.items() == json_tvt_reference.items():
            self.fail()


if __name__ == "__main__":
    unittest.main()
