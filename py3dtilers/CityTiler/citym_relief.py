# -*- coding: utf-8 -*-
"""
Notes on the 3DCityDB database structure

The data is organised in the following way in the database:

- the relief_feature table contains the complex relief objects which are composed
by individual components that can be of different types - TIN/raster etc.)
- the relief_component table contains individual relief components
- the relief_feat_to_rel_comp table establishes a link between individual components and
their "parent" which is a more complex relief object

- the cityobject table contains information about all the objects
- the surface_geometry table contains the geometry of all objects
"""


from citym_cityobject import CityMCityObject, CityMCityObjects


class CityMRelief(CityMCityObject):
    """
    Implementation of the Digital Terrain Model (DTM) objects from the CityGML model.
    """
    def __init__(self):
        super().__init__()


class CityMReliefs(CityMCityObjects):
    """
    A decorated list of CityMRelief type objects.
    """
    def __init__(self):
        super().__init__()

    @staticmethod
    def sql_query_objects(reliefs):
        """
        :param reliefs: a list of CityMRelief type object that should be sought
                        in the database. When this list is empty all the objects
                        encountered in the database are returned.

        :return: a string containing the right sql query that should be executed.
        """
        if not reliefs:
            # No specific reliefs were sought. We thus retrieve all the ones
            # we can find in the database:
            query = "SELECT relief_feature.id, BOX3D(cityobject.envelope) " + \
                    "FROM relief_feature JOIN cityobject ON relief_feature.id=cityobject.id"

        else:
            relief_gmlids = [n.get_gml_id() for n in reliefs]
            relief_gmlids_as_string = "('" + "', '".join(relief_gmlids) + "')"
            query = "SELECT relief_feature.id, BOX3D(cityobject.envelope) " + \
                    "FROM relief_feature JOIN cityobject ON relief_feature.id=cityobject.id" + \
                    "WHERE cityobject.gmlid IN " + relief_gmlids_as_string

        return query

    @staticmethod
    def sql_query_geometries(offset, reliefs_ids=None):
        """
        reliefs_ids is unused but is given in argument to preserve the same structure
        as the sql_query_geometries method of parent class CityMCityObject.

        :return: a string containing the right sql query that should be executed.
        """
        # cityobjects_ids contains ids of reliefs
        query = \
            "SELECT relief_feature.id, ST_AsBinary(ST_Multi(ST_Collect( " + \
            "ST_Translate(surface_geometry.geometry, " + \
            str(-offset[0]) + ", " + str(-offset[1]) + ", " + str(-offset[2]) + \
            ")))) " + \
            "FROM relief_feature JOIN relief_feat_to_rel_comp " + \
            "ON relief_feature.id=relief_feat_to_rel_comp.relief_feature_id " + \
            "JOIN tin_relief " + \
            "ON relief_feat_to_rel_comp.relief_component_id=tin_relief.id " + \
            "JOIN surface_geometry ON surface_geometry.root_id=tin_relief.surface_geometry_id " + \
            "GROUP BY relief_feature.id "

        return query
