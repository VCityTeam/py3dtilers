# -*- coding: utf-8 -*-

from .citym_cityobject import CityMCityObject, CityMCityObjects

class CityMBridge(CityMCityObject):
    """
    Implementation of the Bridge Model objects from the CityGML model.
    """

    def __init__(self, id=None):
        super().__init__(id)


class CityMBridges(CityMCityObjects):
    """
    A decorated list of CityMBridge type objects.
    """

    def __init__(self, objects=None):
        super().__init__(objects)

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
            query = "SELECT bridge.id, BOX3D(cityobject.envelope), cityobject.gmlid " + \
                    "FROM citydb.bridge JOIN citydb.cityobject ON bridge.id=cityobject.id " + \
                    "WHERE bridge.id=bridge.bridge_root_id"
        else:
            bridge_gmlids = [n.get_gml_id() for n in bridges]
            bridge_gmlids_as_string = "('" + "', '".join(bridge_gmlids) + "')"
            query = "SELECT bridge.id, BOX3D(cityobject.envelope), cityobject.gmlid " + \
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
                "surface_geometry.geometry) " + \
                ") " + \
                "FROM citydb.surface_geometry JOIN citydb.bridge " + \
                "ON surface_geometry.root_id=bridge.lod2_multi_surface_id " + \
                "WHERE bridge.bridge_root_id IN " + bridges_ids_arg
        else:
            query = \
                "SELECT bridge.bridge_root_id, ST_AsBinary(ST_Multi(ST_Collect( " + \
                "surface_geometry.geometry) " + \
                ")) " + \
                "FROM citydb.surface_geometry JOIN citydb.bridge " + \
                "ON surface_geometry.root_id=bridge.lod2_multi_surface_id " + \
                "WHERE bridge.bridge_root_id IN " + bridges_ids_arg + " " + \
                "GROUP BY bridge.bridge_root_id "

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
