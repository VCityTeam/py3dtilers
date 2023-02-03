# -*- coding: utf-8 -*-

from .citym_cityobject import CityMCityObject, CityMCityObjects


class CityMBridge(CityMCityObject):
    """
    Implementation of the Bridge Model objects from the CityGML model.
    """

    def __init__(self, database_id=None, gml_id=None):
        super().__init__(database_id, gml_id)
        self.objects_type = CityMBridges


class CityMBridges(CityMCityObjects):
    """
    A decorated list of CityMBridge type objects.
    """

    object_type = CityMBridge

    def __init__(self, features=None):
        super().__init__(features)

    @staticmethod
    def sql_query_objects(bridges):
        """
        :param bridges: a list of CityMbridge type object that should be sought
                        in the database. When this list is empty all the objects
                        encountered in the database are returned.

        :return: a string containing the right SQL query that should be executed.
        """
        if not bridges:
            # No specific bridges were sought. We thus retrieve all the ones
            # we can find in the database:
            query = "SELECT bridge.id, cityobject.gmlid " + \
                    "FROM citydb.bridge JOIN citydb.cityobject ON bridge.id=cityobject.id " + \
                    "WHERE bridge.id=bridge.bridge_root_id"
        else:
            bridge_gmlids = [n.get_gml_id() for n in bridges]
            bridge_gmlids_as_string = "('" + "', '".join(bridge_gmlids) + "')"
            query = "SELECT bridge.id, cityobject.gmlid " + \
                    "FROM citydb.bridge JOIN citydb.cityobject ON bridge.id=cityobject.id " + \
                    "WHERE cityobject.gmlid IN " + bridge_gmlids_as_string + " " + \
                    "AND bridge.id=bridge.bridge_root_id"

        return query

    @staticmethod
    def sql_query_geometries(bridges_ids_arg, split_surfaces=False):
        """
        :param bridges_ids_arg: a formatted list of (city)gml identifier corresponding to
                            objects_type type objects whose geometries are sought.
        :param split_surfaces: a boolean specifying if the surfaces of each bridge will stay
                            splitted or be merged into one geometry

        :return: a string containing the right SQL query that should be executed.
        """
        # Because the 3DCityDB's bridge table regroups both the bridges mixed
        # with their bridge's sub-divisions (bridge is an "abstraction"
        # from which inherits concrete bridge class as well bridge-subdivisions
        # a.k.a. parts) we must first collect all the bridges and their parts:

        if split_surfaces:
            query = \
                "SELECT surface_geometry.id, ST_AsBinary(ST_Multi( " + \
                "surface_geometry.geometry)), " + \
                "objectclass.classname " + \
                "FROM citydb.surface_geometry JOIN citydb.bridge " + \
                "ON surface_geometry.root_id=bridge.lod2_multi_surface_id " + \
                "JOIN citydb.objectclass ON bridge.objectclass_id = objectclass.id " + \
                "WHERE bridge.bridge_root_id IN " + bridges_ids_arg
        else:
            query = \
                "SELECT bridge.bridge_root_id, ST_AsBinary(ST_Multi(ST_Collect( " + \
                "surface_geometry.geometry))), " + \
                "objectclass.classname " + \
                "FROM citydb.surface_geometry JOIN citydb.bridge " + \
                "ON surface_geometry.root_id=bridge.lod2_multi_surface_id " + \
                "JOIN citydb.objectclass ON bridge.objectclass_id = objectclass.id " + \
                "WHERE bridge.bridge_root_id IN " + bridges_ids_arg + " " + \
                "GROUP BY bridge.bridge_root_id, objectclass.classname"

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
            "FROM citydb.surface_geometry JOIN citydb.bridge " + \
            "ON surface_geometry.root_id=bridge.lod2_multi_surface_id " + \
            "WHERE bridge.bridge_root_id = " + str(id) + \
            " GROUP BY bridge.bridge_root_id"

        return query

    @staticmethod
    def sql_query_geometries_with_texture_coordinates(bridges_ids_arg):
        """
        :param bridges_ids_arg: a formatted list of (city)gml identifier corresponding to
                            objects_type type objects whose geometries are sought.
        :return: a string containing the right SQL query that should be executed.
        """
        # Because the 3DCityDB's bridge table regroups both the bridges mixed
        # with their bridge's sub-divisions (bridge is an "abstraction"
        # from which inherits concrete bridge class as well bridge-subdivisions
        # a.k.a. parts) we must first collect all the bridges and their parts:
        query = ("SELECT surface_geometry.id, "
                 "ST_AsBinary(ST_Multi(surface_geometry.geometry)) as geom , "
                 "ST_AsBinary(ST_Multi(ST_Translate("
                 "ST_Scale(textureparam.texture_coordinates, 1, -1), 0, 1))) as uvs, "
                 "tex_image_uri AS uri FROM citydb.bridge JOIN "
                 "citydb.surface_geometry ON surface_geometry.root_id="
                 "bridge.lod2_multi_surface_id JOIN citydb.textureparam ON "
                 "textureparam.surface_geometry_id=surface_geometry.id "
                 "JOIN citydb.surface_data ON textureparam.surface_data_id=surface_data.id "
                 "JOIN citydb.tex_image ON surface_data.tex_image_id=tex_image.id "
                 "WHERE bridge.bridge_root_id IN " + bridges_ids_arg)
        return query
