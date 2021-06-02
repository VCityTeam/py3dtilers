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
        tt.replicate_from(base_transaction)

        # This aggregate transaction includes a single primary transaction
        tt.set_transactions([Test_TemporalPrimaryTransaction.build_sample()])

        return tt

    @classmethod
    def prune_id_from_nested_json_dict(cls, to_prune):
        for k in to_prune.copy().keys():
            if k == 'id':
                # Also all transactions have a mandatory id, it could be that
                # we use this method in a broader context than the one of
                # testing transactions. For example we can test a full tileset
                # that nests some transactions we wish to prune. We thus cannot
                # assume that each to_prune parameter object will have an
                # 'id' dictionary entry. Thus this test.
                del to_prune['id']
                continue
            if not k == 'transactions':
                # This was a PrimaryTransaction
                continue
            for transaction in to_prune['transactions']:
                Test_TemporalTransactionAggregate.prune_id_from_nested_json_dict(transaction)

    def test_json_encoding(self):
        return self.build_sample().to_json()

    def test_build_sample_and_validate(self):
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
        # We do not want to compare the identifiers (that must differ):
        Test_TemporalTransactionAggregate.prune_id_from_nested_json_dict(
                                                                      json_tt)
        Test_TemporalTransactionAggregate.prune_id_from_nested_json_dict(
                                                            json_tt_reference)
        if not json_tt.items() == json_tt_reference.items():
            self.fail()

    def test_append_transaction(self):
        tt = TemporalTransactionAggregate()
        base_transaction = Test_TemporalTransaction.build_sample()
        tt.replicate_from(base_transaction)
        tt.append_transaction(Test_TemporalPrimaryTransaction.build_sample())

if __name__ == "__main__":
    unittest.main()
