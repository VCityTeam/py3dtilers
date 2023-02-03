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


from .citym_cityobject import CityMCityObject, CityMCityObjects


class CityMRelief(CityMCityObject):
    """
    Implementation of the Digital Terrain Model (DTM) objects from the CityGML model.
    """

    def __init__(self, database_id=None, gml_id=None):
        super().__init__(database_id, gml_id)
        self.objects_type = CityMReliefs


class CityMReliefs(CityMCityObjects):
    """
    A decorated list of CityMRelief type objects.
    """

    object_type = CityMRelief

    def __init__(self, features=None):
        super().__init__(features)

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
            query = "SELECT relief_feature.id, cityobject.gmlid " + \
                    "FROM citydb.relief_feature JOIN citydb.cityobject ON relief_feature.id=cityobject.id"

        else:
            relief_gmlids = [n.get_gml_id() for n in reliefs]
            relief_gmlids_as_string = "('" + "', '".join(relief_gmlids) + "')"
            query = "SELECT relief_feature.id, cityobject.gmlid " + \
                    "FROM citydb.relief_feature JOIN citydb.cityobject ON relief_feature.id=cityobject.id" + \
                    "WHERE cityobject.gmlid IN " + relief_gmlids_as_string

        return query

    @staticmethod
    def sql_query_geometries(reliefs_ids=None, split_surfaces=False):
        """
        :param reliefs_ids: a formatted list of (city)gml identifier corresponding to
                            objects_type type objects whose geometries are sought.
        :param split_surfaces: a boolean specifying if the surfaces of each relief tile will stay
                            splitted or be merged into one geometry

        :return: a string containing the right sql query that should be executed.
        """
        # cityobjects_ids contains ids of reliefs
        if split_surfaces:
            query = \
                "SELECT relief_feature.id, ST_AsBinary(ST_Multi(surface_geometry.geometry)), " + \
                "objectclass.classname " + \
                "FROM citydb.relief_feature JOIN citydb.relief_feat_to_rel_comp " + \
                "ON relief_feature.id=relief_feat_to_rel_comp.relief_feature_id " + \
                "JOIN citydb.tin_relief " + \
                "ON relief_feat_to_rel_comp.relief_component_id=tin_relief.id " + \
                "JOIN citydb.surface_geometry ON surface_geometry.root_id=tin_relief.surface_geometry_id " + \
                "JOIN citydb.objectclass ON relief_feature.objectclass_id = objectclass.id " + \
                "WHERE relief_feature.id IN " + reliefs_ids
        else:
            query = \
                "SELECT relief_feature.id, ST_AsBinary(ST_Multi(ST_Collect(surface_geometry.geometry))), " + \
                "objectclass.classname " + \
                "FROM citydb.relief_feature JOIN citydb.relief_feat_to_rel_comp " + \
                "ON relief_feature.id=relief_feat_to_rel_comp.relief_feature_id " + \
                "JOIN citydb.tin_relief " + \
                "ON relief_feat_to_rel_comp.relief_component_id=tin_relief.id " + \
                "JOIN citydb.surface_geometry ON surface_geometry.root_id=tin_relief.surface_geometry_id " + \
                "JOIN citydb.objectclass ON relief_feature.objectclass_id = objectclass.id " + \
                "WHERE relief_feature.id IN " + reliefs_ids + " " + \
                "GROUP BY relief_feature.id, objectclass.classname"

        return query

    @staticmethod
    def sql_query_geometries_with_texture_coordinates(reliefs_ids=None):
        """
        param reliefs_ids: a formatted list of (city)gml identifier corresponding to
                            objects_type type objects whose geometries are sought.
        :return: a string containing the right sql query that should be executed.
        """
        # cityobjects_ids contains ids of reliefs
        query = \
            ("SELECT surface_geometry.id, "
             "ST_AsBinary(ST_Multi(surface_geometry.geometry)) as geom, "
             "ST_AsBinary(ST_Multi(ST_Translate(ST_Scale(textureparam.texture_coordinates, 1, -1), 0, 1))) as uvs, "
             "tex_image_uri AS uri "
             "FROM citydb.relief_feature JOIN citydb.relief_feat_to_rel_comp "
             "ON relief_feature.id=relief_feat_to_rel_comp.relief_feature_id "
             "JOIN citydb.tin_relief "
             "ON relief_feat_to_rel_comp.relief_component_id=tin_relief.id "
             "JOIN citydb.surface_geometry "
             "ON surface_geometry.root_id=tin_relief.surface_geometry_id "
             "JOIN citydb.textureparam "
             "ON textureparam.surface_geometry_id=surface_geometry.id "
             "JOIN citydb.surface_data "
             "ON textureparam.surface_data_id=surface_data.id "
             "JOIN citydb.tex_image "
             "ON surface_data.tex_image_id=tex_image.id "
             "WHERE relief_feature.id IN " + reliefs_ids)
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
            "FROM citydb.relief_feature JOIN citydb.relief_feat_to_rel_comp " + \
            "ON relief_feature.id=relief_feat_to_rel_comp.relief_feature_id " + \
            "JOIN citydb.tin_relief " + \
            "ON relief_feat_to_rel_comp.relief_component_id=tin_relief.id " + \
            "JOIN citydb.surface_geometry ON surface_geometry.root_id=tin_relief.surface_geometry_id " + \
            "WHERE relief_feature.id = " + str(id) + \
            " GROUP BY relief_feature.id"

        return query
