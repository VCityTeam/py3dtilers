# -*- coding: utf-8 -*-
import sys
from abc import ABC
from .threedtiles_notion import ThreeDTilesNotion


class TemporalTransaction(ABC, ThreeDTilesNotion):
    """
    Temporal Transaction is an element of the Temporal TileSet extension.
    """
    def __init__(self):
        ThreeDTilesNotion.__init__(self)

        self.attributes['id'] = None
        self.attributes['startDate'] = None
        self.attributes['endDate'] = None
        self.attributes['tags'] = list()
        self.attributes['source'] = list()
        self.attributes['destination'] = list()

    def set_id(self, identifier):
        self.attributes['id'] = identifier

    def set_start_date(self, date):
        self.attributes['startDate'] = date

    def set_end_date(self, date):
        self.attributes['endDate'] = date

    def set_tags(self, tags):
        if not isinstance(tags, list):
            print("Setting tags requires a list argument.")
            sys.exit(1)
        self.attributes['tags'] = tags

    def append_tag(self, tag):
        self.attributes['tags'].append(tag)

    def set_sources(self, features):
        if not isinstance(features, list):
            print("Setting old features requires a list argument.")
            sys.exit(1)
        self.attributes['source'] = features

    def append_source(self, feature):
        self.attributes['source'].append(feature)

    def set_destinations(self, features):
        if not isinstance(features, list):
            print("Setting new features requires a list argument.")
            sys.exit(1)
        self.attributes['destination'] = features

    def append_destination(self, feature):
        self.attributes['destination'].append(feature)