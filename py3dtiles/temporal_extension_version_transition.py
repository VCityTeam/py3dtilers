# -*- coding: utf-8 -*-
import sys
from .threedtiles_notion import ThreeDTilesNotion


class TemporalVersionTransition(ThreeDTilesNotion):
    """
    Temporal Version Transition is an element of the Temporal TileSet extension.
    """

    def __init__(self):
        ThreeDTilesNotion.__init__(self)

        self.attributes['name'] = None
        self.attributes['startDate'] = None
        self.attributes['endDate'] = None
        self.attributes['from'] = None
        self.attributes['to'] = None
        self.attributes['reason'] = None
        self.attributes['type'] = None
        self.attributes['transactions'] = list()

    def set_name(self, name):
        self.attributes['name'] = name

    def set_start_date(self, date):
        self.attributes['startDate'] = date

    def set_end_date(self, date):
        self.attributes['endDate'] = date

    def set_from(self, from_arg):
        self.attributes['from'] = from_arg

    def set_to(self, to):
        self.attributes['to'] = to

    def set_reason(self, reason):
        self.attributes['reason'] = reason

    def set_type(self, type):
        self.attributes['type'] = type

    def set_transactions(self, transactions):
        if not isinstance(transactions, list):
            print("Setting transactions requires a list argument.")
            sys.exit(1)
        self.attributes['transactions'] = transactions

    def append_transaction(self, transaction):
        self.attributes['transactions'].append(transaction)

