# -*- coding: utf-8 -*-
import sys
from .threedtiles_notion import ThreeDTilesNotion


class TemporalVersion(ThreeDTilesNotion):
    """
    Temporal Version is an element of the Temporal TileSet extension.
    """

    def __init__(self):
        ThreeDTilesNotion.__init__(self)

        self.attributes['id'] = None
        self.attributes['startDate'] = None
        self.attributes['endDate'] = None
        self.attributes['name'] = None
        self.attributes['versionMembers'] = list()
        self.attributes['tags'] = list()

    def set_id(self, id):
        self.attributes['id'] = id

    def set_start_date(self, date):
        self.attributes['startDate'] = date

    def set_end_date(self, date):
        self.attributes['endDate'] = date

    def set_name(self, name):
        self.attributes['name'] = name

    def set_version_members(self, versions):
        if not isinstance(versions, list):
            print("Setting version members requires a list argument.")
            sys.exit(1)
        self.attributes['versionMembers'] = versions

    def append_version_member(self, version):
        self.attributes['versionMembers'].append(version)

    def set_tags(self, tags):
        if not isinstance(tags, list):
            print("Setting tags requires a list argument.")
            sys.exit(1)
        self.attributes['tags'] = tags

    def append_tag(self, tag):
        self.attributes['tags'].append(tag)