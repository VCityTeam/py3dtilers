# -*- coding: utf-8 -*-
import sys
from .temporal_extension_transaction import TemporalTransaction


class TemporalPrimaryTransaction(TemporalTransaction):
    """
    Temporal Primary Transaction represents the atomic Transaction.
    """
    def __init__(self):
        TemporalTransaction.__init__(self)
        self.define_attributes()

    def define_attributes(self):
        # Refer to TemporalTransaction::replicate_from()
        self.attributes['type'] = None

    def set_type(self, new_type):
        if new_type not in \
                ["creation", "demolition", "modification", "union", "division"]:
            print("Unknown type of transaction.")
            sys.exit(1)
        self.attributes['type'] = new_type
