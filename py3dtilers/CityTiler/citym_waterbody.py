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


from .citym_cityobject import CityMCityObject, CityMCityObjects


class CityMWaterBody(CityMCityObject):
    """
    Implementation of the Water Body Model objects from the CityGML model.
    """

    def __init__(self, database_id=None, gml_id=None):
        super().__init__(database_id, gml_id)
        self.objects_type = CityMWaterBodies


class CityMWaterBodies(CityMCityObjects):
    """
    A decorated list of CityMWaterBody type objects.
    """

    object_type = CityMWaterBody

    def __init__(self, features=None):
        super().__init__(features)

    @staticmethod
    def sql_query_objects(waterbodies):
        """
        :param waterbodies: a list of CityMWaterBody type object that should be sought
                        in the database. When this list is empty all the objects
                        encountered in the database are returned.
        :param citygml_ids: a list of cityGML IDs. If the list isn't empty, we keep
                        only the objects of the list

        :return: a string containing the right sql query that should be executed.
        """
        if not waterbodies:
            # No specific waterbodies were sought. We thus retrieve all the ones
            # we can find in the database:
            query = "SELECT waterbody.id, cityobject.gmlid " + \
                    "FROM citydb.waterbody JOIN citydb.cityobject ON waterbody.id=cityobject.id"
        else:
            waterbody_gmlids = [n.get_gml_id() for n in waterbodies]
            waterbody_gmlids_as_string = "('" + "', '".join(waterbody_gmlids) + "')"
            query = "SELECT waterbody.id, cityobject.gmlid " + \
                    "FROM citydb.waterbody JOIN citydb.cityobject ON waterbody.id=cityobject.id" + \
                    "WHERE cityobject.gmlid IN " + waterbody_gmlids_as_string

        return query

    @staticmethod
    def sql_query_geometries(waterbodies_ids=None, split_surfaces=False):
        """
        :param waterbodies_ids: a formatted list of (city)gml identifier corresponding to
                            objects_type type objects whose geometries are sought.
        :param split_surfaces: a boolean specifying if the surfaces of each water body tile will stay
                            splitted or be merged into one geometry

        :return: a string containing the right sql query that should be executed.
        """
        # cityobjects_ids contains ids of waterbodies
        if split_surfaces:
            query = \
                "SELECT waterbody.id, ST_AsBinary(ST_Multi(surface_geometry.geometry)), " + \
                "objectclass.classname " + \
                "FROM citydb.waterbody JOIN citydb.waterbod_to_waterbnd_srf " + \
                "ON waterbody.id=waterbod_to_waterbnd_srf.waterbody_id " + \
                "JOIN citydb.waterboundary_surface " + \
                "ON waterbod_to_waterbnd_srf.waterboundary_surface_id=waterboundary_surface.id " + \
                "JOIN citydb.surface_geometry ON surface_geometry.root_id=waterboundary_surface.lod3_surface_id " + \
                "JOIN citydb.objectclass ON waterboundary_surface.objectclass_id = objectclass.id " + \
                "WHERE waterbody.id IN " + waterbodies_ids
        else:
            query = \
                "SELECT waterbody.id, ST_AsBinary(ST_Multi(ST_Collect(surface_geometry.geometry))), " + \
                "objectclass.classname " + \
                "FROM citydb.waterbody JOIN citydb.waterbod_to_waterbnd_srf " + \
                "ON waterbody.id=waterbod_to_waterbnd_srf.waterbody_id " + \
                "JOIN citydb.waterboundary_surface " + \
                "ON waterbod_to_waterbnd_srf.waterboundary_surface_id=waterboundary_surface.id " + \
                "JOIN citydb.surface_geometry ON surface_geometry.root_id=waterboundary_surface.lod3_surface_id " + \
                "JOIN citydb.objectclass ON waterbody.objectclass_id = objectclass.id " + \
                "WHERE waterbody.id IN " + waterbodies_ids + " " + \
                "GROUP BY waterbody.id, objectclass.classname"

        return query

    @staticmethod
    def sql_query_geometries_with_texture_coordinates(water_bodies_ids=None):
        """
        param water_bodies_ids: a formatted list of (city)gml identifier corresponding to
                            objects_type type objects whose geometries are sought.
        :return: a string containing the right sql query that should be executed.
        """
        # cityobjects_ids contains ids of water_bodies
        query = \
            ("SELECT surface_geometry.id, "
             "ST_AsBinary(ST_Multi(surface_geometry.geometry)) as geom, "
             "ST_AsBinary(ST_Multi(ST_Translate(ST_Scale(textureparam.texture_coordinates, 1, -1), 0, 1))) as uvs, "
             "tex_image_uri AS uri "
             "FROM citydb.waterbody JOIN citydb.waterbod_to_waterbnd_srf "
             "ON waterbody.id=waterbod_to_waterbnd_srf.waterbody_id "
             "JOIN citydb.waterboundary_surface "
             "ON waterbod_to_waterbnd_srf.waterboundary_surface_id=waterboundary_surface.id "
             "JOIN citydb.surface_geometry "
             "ON surface_geometry.root_id=waterboundary_surface.lod3_surface_id "
             "JOIN citydb.textureparam "
             "ON textureparam.surface_geometry_id=surface_geometry.id "
             "JOIN citydb.surface_data "
             "ON textureparam.surface_data_id=surface_data.id "
             "JOIN citydb.tex_image "
             "ON surface_data.tex_image_id=tex_image.id "
             "WHERE waterbody.id IN " + water_bodies_ids)
        return query

    @staticmethod
    def sql_query_centroid(id):
        """
        param id: the ID of the cityGML object
        return: the [x, y, z] coordinates of the centroid of the cityGML object
        """

        query = \
            "SELECT " + \
            "ST_X(ST_3DClosestPoint(ST_Multi(ST_Collect(surface_geometry.geometry)) " + \
            ",ST_Centroid(ST_Multi(ST_Collect(surface_geometry.geometry))))), " + \
            "ST_Y(ST_3DClosestPoint(ST_Multi(ST_Collect(surface_geometry.geometry)) " + \
            ",ST_Centroid(ST_Multi(ST_Collect(surface_geometry.geometry))))), " + \
            "ST_Z(ST_3DClosestPoint(ST_Multi(ST_Collect(surface_geometry.geometry)) " + \
            ",ST_Centroid(ST_Multi(ST_Collect(surface_geometry.geometry))))) " + \
            "FROM citydb.waterbody JOIN citydb.waterbod_to_waterbnd_srf " + \
            "ON waterbody.id=waterbod_to_waterbnd_srf.waterbody_id " + \
            "JOIN citydb.waterboundary_surface " + \
            "ON waterbod_to_waterbnd_srf.waterboundary_surface_id=waterboundary_surface.id " + \
            "JOIN citydb.surface_geometry ON surface_geometry.root_id=waterboundary_surface.lod3_surface_id " + \
            "WHERE waterbody.id = " + str(id) + \
            " GROUP BY waterbody.id"

        return query
