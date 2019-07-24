# -*- coding: utf-8 -*-
from citym_cityobject import CityMCityObject, CityMCityObjects


class CityMBuilding(CityMCityObject):
    def __init__(self):
        super().__init__()


class CityMBuildings(CityMCityObjects):
    with_bth = False

    def __init__(self):
        super().__init__()

    @staticmethod
    def set_bth():
        CityMBuildings.with_bth = True

    @staticmethod
    def is_bth_set():
        return CityMBuildings.with_bth

    @staticmethod
    def sql_query_objects(buildings):
        """
        FIXME
        :param buildings:
        :return:
        """
        if not buildings:
            # No specific buildings were sought. We thus retrieve all the ones
            # we can find in the database:
            query = "SELECT building.id, BOX3D(cityobject.envelope) " + \
                    "FROM building JOIN cityobject ON building.id=cityobject.id " + \
                    "WHERE building.id=building.building_root_id"
        else:
            building_gmlids = [n.get_gml_id() for n in buildings]
            building_gmlids_as_string = "('" + "', '".join(building_gmlids) + "')"
            query = "SELECT building.id, BOX3D(cityobject.envelope), cityobject.gmlid " + \
                    "FROM building JOIN cityobject ON building.id=cityobject.id " + \
                    "WHERE cityobject.gmlid IN " + building_gmlids_as_string + " " + \
                    "AND building.id=building.building_root_id"

        return query

    @staticmethod
    def sql_query_geometries(offset, buildings_ids_arg):
        """
        FIXME
        :return:
        """
        # cityobjects_ids contains ids of buildings

        # Because the 3DCityDB's Building table regroups both the buildings mixed
        # with their building's sub-divisions (Building is an "abstraction"
        # from which inherits concrete building class as well building-subdivisions
        # a.k.a. parts) we must first collect all the buildings and their parts:

        query = \
            "SELECT building.building_root_id, ST_AsBinary(ST_Multi(ST_Collect( " + \
            "ST_Translate(surface_geometry.geometry, " + \
            str(-offset[0]) + ", " + str(-offset[1]) + ", " + str(-offset[2]) + \
            ")))) " + \
            "FROM surface_geometry JOIN thematic_surface " + \
            "ON surface_geometry.root_id=thematic_surface.lod2_multi_surface_id " + \
            "JOIN building ON thematic_surface.building_id = building.id " + \
            "WHERE building.building_root_id IN " + buildings_ids_arg + " " + \
            "GROUP BY building.building_root_id "

        return query
