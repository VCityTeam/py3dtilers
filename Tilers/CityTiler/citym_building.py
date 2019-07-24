# -*- coding: utf-8 -*-
"""
Notes on the 3DCityDB database structure

The data is organised in the following way in the database:

- the building table contains the "abstract" building
subdivisions (building, building part)
- the thematic_surface table contains all the surface objects (wall,
roof, floor), with links to the building object it belongs to
and the geometric data in the surface_geometry table

- the cityobject table contains information about all the objects
- the surface_geometry table contains the geometry of all objects

"""


from citym_cityobject import CityMCityObject, CityMCityObjects


class CityMBuilding(CityMCityObject):
    """
    Implementation of the Building Model objects from the CityGML model.
    """
    def __init__(self):
        super().__init__()


class CityMBuildings(CityMCityObjects):
    """
    A decorated list of CityMBuilding type objects.
    """
    # with_bth value is set to False by default. the value of this variable
    # depends on the command line optional argument "--With_BTH" of CityTiler.
    with_bth = False

    def __init__(self):
        super().__init__()

    @classmethod
    def set_bth(cls):
        cls.with_bth = True

    @classmethod
    def is_bth_set(cls):
        return cls.with_bth

    @staticmethod
    def sql_query_objects(buildings):
        """
        :param buildings: a list of CityMBuilding type object that should be sought
                        in the database. When this list is empty all the objects
                        encountered in the database are returned.

        :return: a string containing the right SQL query that should be executed.
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
        :param offset: the offset (a 3D "vector" of floats) by which the
                       geographical coordinates should be translated (the
                       computation is done at the GIS level).
        :param buildings_ids_arg: a formatted list of (city)gml identifier corresponding to
                            objects_type type objects whose geometries are sought.

        :return: a string containing the right SQL query that should be executed.
        """
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
