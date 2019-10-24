# -*- coding: utf-8 -*-

import json
import unittest
from py3dtiles import TemporalTransactionAggregate
from py3dtiles import HelperTest
from .test_temporal_extension_transaction import Test_TemporalTransaction
from .test_temporal_extension_primary_transaction \
                                        import Test_TemporalPrimaryTransaction


class Test_TemporalTransactionAggregate(unittest.TestCase):
    """
    Transaction Aggregate extension of the Temporal applicative extension
    """
    def test_basics(self):
        helper = HelperTest(lambda x: TemporalTransactionAggregate().validate(x))
        helper.sample_file_names.append(
                      'temporal_extension_transaction_aggregate_sample.json')
        if not helper.check():
            self.fail()

    @classmethod
    def build_sample(cls):
        """
        Programmatically define the reference a sample.
        :return: the sample as TemporalAggregateTransaction object.
        """
        tt = TemporalTransactionAggregate()
        base_transaction = Test_TemporalTransaction.build_sample()
        # Copy the base class (sample) object within the sample we build. Note
        # that shallow copy is enough because the base case _sample_ has no
        # nested attribute values.
        tt.__dict__ = dict(base_transaction.__dict__)

        # This aggregate transaction includes a single primary transaction
        tt.set_transactions([Test_TemporalPrimaryTransaction.build_sample()])

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
                        'temporal_extension_transaction_aggregate_sample.json')
        if not json_tt.items() == json_tt_reference.items():
            self.fail()


if __name__ == "__main__":
    unittest.main()
