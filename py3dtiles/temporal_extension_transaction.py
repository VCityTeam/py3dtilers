# -*- coding: utf-8 -*-
import sys
import copy
from .threedtiles_notion import ThreeDTilesNotion

class TemporalTransaction(ThreeDTilesNotion):
    """
    Temporal Transaction is an element of the Temporal TileSet extension.
    """
    # Total number of created transactions (as opposed to existing transactions
    # the difference being that the counter doesn't take into account the
    # deleted transactions)
    transactions_counter = 0

    def __init__(self):
        ThreeDTilesNotion.__init__(self)

        # The identifier is defaulted with a value handled by the class.
        # Yet the identifier is only handled partially by the class since
        # its value can be overwritten (and without warning in doing so)
        self.attributes['id'] = str(TemporalTransaction.transactions_counter)
        TemporalTransaction.transactions_counter += 1
        self.attributes['startDate'] = None
        self.attributes['endDate'] = None
        self.attributes['tags'] = list()
        self.attributes['source'] = list()
        self.attributes['destination'] = list()

    def define_attributes(self):
        print('This method should have been overloaded in derived class !')
        sys.exit(1)

    def replicate_from(self, to_be_replicated):
        """
        Overwrite the attributes of this object with the ones of the given
        (argument) object.
        :param to_be_replicated: the object attributes that must be replicated
                                 to the ones of self.
        """
        # We wish to copy all the attributes BUT the identifier (because the
        # identifier must remain unique). We thus save the 'id' attribute
        # in order to set it back to its initial value after the copy
        original_id = self.attributes['id']
        self.attributes = copy.deepcopy(to_be_replicated.attributes)
        self.attributes['id'] = original_id
        # Because the attributes _dictionary_ was overwritten we have to
        # redefine the derived class(es) attributes
        self.define_attributes()

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