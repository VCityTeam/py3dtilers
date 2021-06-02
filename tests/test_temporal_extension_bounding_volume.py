# -*- coding: utf-8 -*-

import json
import unittest
from py3dtiles import TemporalBoundingVolume, HelperTest
from tests.test_bounding_volume import Test_Bounding_Volume


class Test_TemporalBoundingVolume(unittest.TestCase):
    """
    Batch Table extension of the Temporal applicative extension
    """
    def test_basics(self):
        helper = HelperTest(lambda x: TemporalBoundingVolume().validate(x))
        helper.sample_file_names.append(
                      'temporal_extension_bounding_volume_sample.json')
        if not helper.check():
            self.fail()

    def build_sample(self):
        """
        Programmatically define the reference a sample.
        :return: the sample as TemporalBatchTable object.
        """
        tbv = TemporalBoundingVolume()

        tbv.set_start_date("2018-01-01")
        tbv.set_end_date("2019-01-01")

        return tbv

    def test_json_encoding(self):
        return self.build_sample().to_json()

    def test_tbv_build_sample_and_validate(self):
        if not self.build_sample().validate():
            self.fail()

    def test_build_sample_and_compare_reference_file(self):
        """
        Build the sample, load the version from the reference file and
        compare them (in memory as opposed to "diffing" files)
        """
        json_tbv = json.loads(self.build_sample().to_json())
        json_tbv_reference = HelperTest().load_json_reference_file(
                            'temporal_extension_bounding_volume_sample.json')
        if not json_tbv.items() == json_tbv_reference.items():
            self.fail()

    def test_plug_extension_into_simple_batch_table(self):
        bv = Test_Bounding_Volume.build_box_sample()
        tbv = self.build_sample()
        bv.add_extension(tbv)
        bv.validate()

        # Voluntarily introduce a mistake in the added extension in order
        # to make sure that the extension is really validated. If bv.validate()
        # is still true then the validation didn't check the extension and
        # hence the test must fail.
        tbv.set_start_date([])
        if bv.validate(quiet=True):
            self.fail()


if __name__ == "__main__":
    unittest.main()
