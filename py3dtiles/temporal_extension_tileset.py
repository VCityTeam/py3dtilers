# -*- coding: utf-8 -*-
import sys
from .extension import Extension
from .threedtiles_notion import ThreeDTilesNotion
from .temporal_extension_transaction import TemporalTransaction


class TemporalTileSet(Extension, ThreeDTilesNotion):
    """
    Temporal Tile Set is an Extension of a Tile Set.
    """

    def __init__(self):
        Extension.__init__(self, '3DTILES_temporal_tileset')
        ThreeDTilesNotion.__init__(self)

        self.attributes['startDate'] = None
        self.attributes['endDate'] = None
        self.attributes['transactions'] = list()
        self.attributes['versions'] = list()
        self.attributes['versionTransitions'] = list()

    def set_start_date(self, date):
        self.attributes['startDate'] = date

    def set_end_date(self, date):
        self.attributes['endDate'] = date

    def set_transactions(self, transactions):
        if not isinstance(transactions, list):
            print("Setting transactions requires a list argument.")
            sys.exit(1)
        self.attributes['transactions'] = transactions

    def append_transaction(self, transaction):
        if not isinstance(transaction, TemporalTransaction):
            print('Append_transaction requires a transaction argument.')
            sys.exit(1)
        self.attributes['transactions'].append(transaction)

    def set_versions(self, versions):
        if not isinstance(versions, list):
            print("Setting versions requires a list argument.")
            sys.exit(1)
        self.attributes['versions'] = versions

    def append_version(self, version):
        self.attributes['versions'].append(version)

    def set_version_transitions(self, version_transitions):
        if not isinstance(version_transitions, list):
            print("Setting version transitions requires a list argument.")
            sys.exit(1)
        self.attributes['versionTransitions'] = version_transitions

    def append_version_transition(self, version_transition):
        self.attributes['versionTransitions'].append(version_transition)