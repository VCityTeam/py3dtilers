# -*- coding: utf-8 -*-
import sys
from .extension import Extension
from .threedtiles_notion import ThreeDTilesNotion


class TemporalBatchTable(Extension, ThreeDTilesNotion):
    """
    Temporal Batch Table is an Extension of a Batch Table.
    """

    def __init__(self):
        Extension.__init__(self, '3DTILES_temporal')
        ThreeDTilesNotion.__init__(self)

        self.attributes['startDates'] = list()
        self.attributes['endDates'] = list()
        self.attributes['featureIds'] = list()

    def set_start_dates(self, dates):
        if not isinstance(dates, list):
            print("Setting startDates requires a list argument.")
            sys.exit(1)
        self.attributes['startDates'] = dates

    def append_start_date(self, date):
        self.attributes['startDates'].append(date)

    def set_end_dates(self, dates):
        if not isinstance(dates, list):
            print("Setting endDates requires a list argument.")
            sys.exit(1)
        self.attributes['endDates'] = dates

    def append_end_date(self, date):
        self.attributes['endDates'].append(date)

    def set_feature_ids(self, ids):
        if not isinstance(ids, list):
            print("Setting featureIds requires a list argument.")
            sys.exit(1)
        self.attributes['featureIds'] = ids

    def append_feature_id(self, id):
        self.attributes['featureIds'].append(id)