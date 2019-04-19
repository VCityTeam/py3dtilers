# -*- coding: utf-8 -*-
import sys
from .threedtiles_notion import ThreeDTilesNotion


class TemporalTransaction(ThreeDTilesNotion):
    """
    Temporal Transaction is an element of the Temporal TileSet extension.
    """
    def __init__(self):
        ThreeDTilesNotion.__init__(self)

        self.attributes['id'] = None
        self.attributes['startDate'] = None
        self.attributes['endDate'] = None
        self.attributes['type'] = None
        self.attributes['tags'] = list()
        self.attributes['oldFeatures'] = list()
        self.attributes['newFeatures'] = list()

    def set_id(self, id):
        self.attributes['id'] = id

    def set_start_date(self, date):
        self.attributes['startDate'] = date

    def set_end_date(self, date):
        self.attributes['endDate'] = date

    def set_type(self, type):
        self.attributes['type'] = type

    def set_tags(self, tags):
        if not isinstance(tags, list):
            print("Setting tags requires a list argument.")
            sys.exit(1)
        self.attributes['tags'] = tags

    def append_tag(self, tag):
        self.attributes['tags'].append(tag)

    def set_old_features(self, features):
        if not isinstance(features, list):
            print("Setting old features requires a list argument.")
            sys.exit(1)
        self.attributes['oldFeatures'] = features

    def append_old_feature(self, feature):
        self.attributes['oldFeatures'].append(feature)

    def set_new_features(self, features):
        if not isinstance(features, list):
            print("Setting new features requires a list argument.")
            sys.exit(1)
        self.attributes['newFeatures'] = features

    def append_new_feature(self, feature):
        self.attributes['newFeatures'].append(feature)