# -*- coding: utf-8 -*-
import sys
from .extension import Extension
from .threedtiles_notion import ThreeDTilesNotion
from .temporal_extension_utils import temporal_extract_bounding_dates
from .bounding_volume_box import BoundingVolumeBox   # Ooops

class TemporalBoundingVolume(Extension, ThreeDTilesNotion):
    """
    Temporal Bounding Volume is an Extension of a Bounding Volume.
    """

    def __init__(self):
        Extension.__init__(self, '3DTILES_temporal')
        ThreeDTilesNotion.__init__(self)

        self.attributes['startDate'] = None
        self.attributes['endDate'] = None

    def set_start_date(self, date):
        self.attributes['startDate'] = date

    def get_start_date(self):
        return self.attributes['startDate']

    def set_end_date(self, date):
        self.attributes['endDate'] = date

    def get_end_date(self):
        return self.attributes['endDate']

    @classmethod
    def get_children(cls, owner):
        children_tbv = list()
        for bounding_volume in BoundingVolumeBox.get_children(owner):
            temporal_bv = bounding_volume.get_extension('3DTILES_temporal')
            if not temporal_bv:
                print(f'This bounding volume lacks its temporal extension.')
                print('Exiting')
                sys.exit(1)
            children_tbv.append(temporal_bv)
        return children_tbv

    def sync_with_children(self, owner):
        bounding_dates = temporal_extract_bounding_dates(
            TemporalBoundingVolume.get_children(owner))
        self.set_start_date(bounding_dates['start_date'])
        self.set_end_date(bounding_dates['end_date'])