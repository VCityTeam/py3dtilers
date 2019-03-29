# -*- coding: utf-8 -*-

import json
import unittest
from py3dtiles import TemporalVersion, HelperTest


class Test_TemporalVersion(unittest.TestCase):
    """
    Batch Table extension of the Temporal applicative extension
    """
    def test_basics(self):
        helper = HelperTest(lambda x: TemporalVersion().validate(x))
        helper.sample_file_names.append(
                      'temporal_extension_version_sample.json')
        if not helper.check():
            self.fail()

    @classmethod
    def build_sample(cls):
        """
        Programmatically define the reference a sample.
        :return: the sample as TemporalBatchTable object.
        """
        tv = TemporalVersion()

        tv.set_id(0)
        tv.set_start_date("2018-01-01")
        tv.set_end_date("2019-01-01")
        tv.set_name("some version name")
        tv.set_version_members(["version 1", "version 2"])
        tv.append_version_member("version 3")
        tv.set_tags(["some tag version"])
        tv.append_tag("some other tag version")

        return tv

    def test_json_encoding(self):
        return self.build_sample().to_json()

    def test_tv_build_sample_and_validate(self):
        if not self.build_sample().validate():
            self.fail()

    def test_build_sample_and_compare_reference_file(self):
        """
        Build the sample, load the version from the reference file and
        compare them (in memory as opposed to "diffing" files)
        """
        json_tbt = json.loads(self.build_sample().to_json())
        json_tbt_reference = HelperTest().load_json_reference_file(
                            'temporal_extension_version_sample.json')
        if not json_tbt.items() == json_tbt_reference.items():
            self.fail()


if __name__ == "__main__":
    unittest.main()
