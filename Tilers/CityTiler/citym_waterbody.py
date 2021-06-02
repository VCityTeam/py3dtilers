# -*- coding: utf-8 -*-
"""
Notes on the 3DCityDB database structure

The data is organised in the following way in the database:

- the waterbody table contains the "complex" water body objects which has one
 obligatory attribute (boundary_surface) and sometimes optional attributes
- the waterboundary_surface table contains information about the geometry individual boundary_surface
- the waterbod_to_waterbnd_srf table establishes a link between individual boundary surfaces and
water body objects

- the cityobject table contains information about all the objects
- the surface_geometry table contains the geometry of all objects
"""


from citym_cityobject import CityMCityObject, CityMCityObjects


class CityMWaterBody(CityMCityObject):
    """
    Implementation of the Water Body Model objects from the CityGML model.
    """
    def __init__(self):
        super().__init__()


class CityMWaterBodies(CityMCityObjects):
    """
    A decorated list of CityMWaterBody type objects.
    """
    def __init__(self):
        super().__init__()

    @staticmethod
    def sql_query_objects(waterbodies):
        """
        :param waterbodies: a list of CityMWaterBody type object that should be sought
                        in the database. When this list is empty all the objects
                        encountered in the database are returned.

        :return: a string containing the right sql query that should be executed.
        """
        if not waterbodies:
            # No specific waterbodies were sought. We thus retrieve all the ones
            # we can find in the database:
            query = "SELECT waterbody.id, BOX3D(cityobject.envelope) " + \
                    "FROM waterbody JOIN cityobject ON waterbody.id=cityobject.id"

        else:
            waterbody_gmlids = [n.get_gml_id() for n in waterbodies]
            waterbody_gmlids_as_string = "('" + "', '".join(waterbody_gmlids) + "')"
            query = "SELECT waterbody.id, BOX3D(cityobject.envelope) " + \
                    "FROM waterbody JOIN cityobject ON waterbody.id=cityobject.id" + \
                    "WHERE cityobject.gmlid IN " + waterbody_gmlids_as_string

        return query

    @staticmethod
    def sql_query_geometries(offset, waterbodies_ids=None):
        """
        waterbodies_ids is unused but is given in argument to preserve the same structure
        as the sql_query_geometries method of parent class CityMCityObject.

        :return: a string containing the right sql query that should be executed.
        """
        # cityobjects_ids contains ids of waterbodies
        query = \
            "SELECT waterbody.id, ST_AsBinary(ST_Multi(ST_Collect( " + \
            "ST_Translate(surface_geometry.geometry, " + \
            str(-offset[0]) + ", " + str(-offset[1]) + ", " + str(-offset[2]) + \
            ")))) " + \
            "FROM waterbody JOIN waterbod_to_waterbnd_srf " + \
            "ON waterbody.id=waterbod_to_waterbnd_srf.waterbody_id " + \
            "JOIN waterboundary_surface " + \
            "ON waterbod_to_waterbnd_srf.waterboundary_surface_id=waterboundary_surface.id " + \
            "JOIN surface_geometry ON surface_geometry.root_id=waterboundary_surface.lod3_surface_id " + \
            "GROUP BY waterbody.id "

        return query
