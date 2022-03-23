from .citym_building import CityMBuilding


class TemporalBuilding(CityMBuilding):

    def __init__(self, id=None):
        """
        TemporalBuilding is a building extended with the information required
        by the 3DTiles Temporal Extension that complement a building with
        the respective values of its creation and deletion dates.
        """
        CityMBuilding.__init__(self, id)
        # The date at which the building was constructed
        self.start_date = None
        # The date at which the building was destructed
        self.end_date = None
        # A string used as (global) Node identifier i.e. valid across a
        # set of citygml databases
        self.temporal_id = None

    def set_start_date(self, start_date):
        self.start_date = start_date

    def get_start_date(self):
        return self.start_date

    def set_end_date(self, end_date):
        self.end_date = end_date

    def get_end_date(self):
        return self.end_date

    def set_temporal_id(self, temporal_id):
        self.temporal_id = temporal_id

    def get_temporal_id(self):
        return self.temporal_id

    def get_time_stamp(self):
        # This should be of type date and by default is manipulated as string:
        return self.temporal_id.split('::')[0]

    def get_geom(self, user_arguments=None, feature_list=None, material_indexes=dict):
        """
        Get the geometry of the feature.
        :return: a boolean
        """
        if self.geom is not None and len(self.geom.triangles) > 0 and len(self.get_geom_as_triangles()) > 0:
            return [self]
        else:
            return []
