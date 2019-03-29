# -*- coding: utf-8 -*-
from .extension import Extension
from .threedtiles_notion import ThreeDTilesNotion


class TemporalBoundingVolume(Extension, ThreeDTilesNotion):
    """
    Temporal Bounding Volume is an Extension of a Bounding Volume.
    """

    def __init__(self):
        Extension.__init__(self, '3DTILES_temporal_bounding_volume')
        ThreeDTilesNotion.__init__(self)

        self.attributes['startDate'] = None
        self.attributes['endDate'] = None

    def set_start_date(self, date):
        self.attributes['startDate'] = date

    def set_end_date(self, date):
        self.attributes['endDate'] = date