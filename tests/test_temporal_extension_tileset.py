# -*- coding: utf-8 -*-

import json
import unittest
from py3dtiles import TemporalTileSet
from tests.test_temporal_extension_primary_transaction \
                                        import Test_TemporalPrimaryTransaction
from tests.test_temporal_extension_version import Test_TemporalVersion
from tests.test_temporal_extension_version_transition \
                                         import Test_TemporalVersionTransition
from tests.test_temporal_extension_transaction_aggregate \
                                      import Test_TemporalTransactionAggregate
from tests.test_tileset import Test_TileSet
from py3dtiles import HelperTest


class Test_TemporalTileSet(unittest.TestCase):
    """
    Batch Table extension of the Temporal applicative extension
    """
    def test_basics(self):
        helper = HelperTest(lambda x: TemporalTileSet().validate(x))
        helper.sample_file_names.append(
                      'temporal_extension_tileset_sample.json')
        if not helper.check():
            self.fail()

    @classmethod
    def build_sample(cls):
        """
        Programmatically define the reference a sample.
        :return: the sample as TemporalBatchTable object.
        """
        tts = TemporalTileSet()

        tts.set_start_date("2018-01-01")
        tts.set_end_date("2019-01-01")
        tts.set_transactions([Test_TemporalPrimaryTransaction.build_sample()])
        tts.set_versions([Test_TemporalVersion.build_sample()])
        tts.set_version_transitions([Test_TemporalVersionTransition.build_sample()])

        return tts

    def test_json_encoding(self):
        return self.build_sample().to_json()

    def test_tts_build_sample_and_validate(self):
        if not self.build_sample().validate():
            self.fail()

    def test_build_sample_and_compare_reference_file(self):
        """
        Build the sample, load the version from the reference file and
        compare them (in memory as opposed to "diffing" files)
        """
        json_tbt = json.loads(self.build_sample().to_json())
        json_tbt_reference = HelperTest().load_json_reference_file(
                            'temporal_extension_tileset_sample.json')
        # We do not want to compare the possible transaction identifiers:
        Test_TemporalTransactionAggregate.prune_id_from_nested_json_dict(
                                                                    json_tbt)
        Test_TemporalTransactionAggregate.prune_id_from_nested_json_dict(
                                                          json_tbt_reference)
        if not json_tbt.items() == json_tbt_reference.items():
            self.fail()

    def test_plug_extension_into_simple_tileset(self):
        ts = Test_TileSet.build_sample()
        tts = self.build_sample()
        ts.add_extension(tts)
        ts.validate()

        # Voluntarily introduce a mistake in the added extension in order
        # to make sure that the extension is really validated. If bt.validate()
        # is still true then the validation didn't check the extension and
        # hence the test must fail.
        tts.set_start_date(["2018-01-01"])
        if ts.validate(quiet=True):
            self.fail()


if __name__ == "__main__":
    unittest.main()
