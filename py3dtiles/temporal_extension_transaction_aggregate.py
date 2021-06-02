# -*- coding: utf-8 -*-
import sys
from .temporal_extension_transaction import TemporalTransaction


class TemporalTransactionAggregate(TemporalTransaction):
    """
    An aggregate of Temporal Primary Transactions (since the base class is
    abstract).
    """
    def __init__(self):
        TemporalTransaction.__init__(self)
        self.define_attributes()

    def define_attributes(self):
        # Refer to TemporalTransaction::replicate_from()
        self.attributes['transactions'] = list()

    def set_transactions(self, transactions):
        if not isinstance(transactions, list):
            print("Setting transactions requires a list argument.")
            sys.exit(1)
        self.attributes['transactions'] = transactions

    def append_transaction(self, transaction):
        self.attributes['transactions'].append(transaction)
