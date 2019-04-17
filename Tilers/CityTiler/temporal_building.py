from building import Building


class TemporalBuilding(Building):

    def __init__(self):
        """
        TemporalBuilding is a building extended with the information required
        by the 3DTiles Temporal Extension that complement a building with
        the respective values of its creation and deletion dates.
        """
        Building.__init__(self)
        # The date at which the building was constructed
        self.creation_date = None
        # The date at which the building was destructed
        self.deletion_date = None
        # A string used as (global) Node identifier i.e. valid across a
        # set of citygml databases
        self.temporal_id = None

    def set_creation_date(self, creation_date):
        self.creation_date = creation_date

    def set_deletion_date(self, deletion_date):
        self.deletion_date = deletion_date

    def set_temporal_id(self, temporal_id):
        self.temporal_id = temporal_id

    def get_temporal_id(self):
        return self.temporal_id

    def get_time_stamp(self):
        # This should be of type date and by default is manipulated as string:
        return self.temporal_id.split('::')[0]