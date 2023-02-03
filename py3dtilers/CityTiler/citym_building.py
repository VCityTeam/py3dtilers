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
from py3dtiles import TemporalBatchTable, TemporalBoundingVolume
from py3dtiles import temporal_extract_bounding_dates
from .citym_cityobject import CityMCityObject, CityMCityObjects
from .database_accesses_batch_table_hierarchy import create_batch_table_hierarchy


class CityMBuilding(CityMCityObject):
    """
    Implementation of the Building Model objects from the CityGML model.
    """

    def __init__(self, database_id=None, gml_id=None):
        super().__init__(database_id, gml_id)
        self.objects_type = CityMBuildings


class CityMBuildings(CityMCityObjects):
    """
    A decorated list of CityMBuilding type objects.
    """

    object_type = CityMBuilding

    # with_bth value is set to False by default. the value of this variable
    # depends on the command line optional argument "--With_BTH" of CityTiler.
    with_bth = False

    def __init__(self, features=None):
        super().__init__(features)

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
            query = "SELECT building.id, cityobject.gmlid " + \
                    "FROM citydb.building JOIN citydb.cityobject ON building.id=cityobject.id " + \
                    "WHERE building.id=building.building_root_id"
        else:
            building_gmlids = [n.get_gml_id() for n in buildings]
            building_gmlids_as_string = "('" + "', '".join(building_gmlids) + "')"
            query = "SELECT building.id, cityobject.gmlid " + \
                    "FROM citydb.building JOIN citydb.cityobject ON building.id=cityobject.id " + \
                    "WHERE cityobject.gmlid IN " + building_gmlids_as_string + " " + \
                    "AND building.id=building.building_root_id"

        return query

    @staticmethod
    def sql_query_geometries(buildings_ids_arg, split_surfaces=False):
        """
        :param buildings_ids_arg: a formatted list of (city)gml identifier corresponding to
                            objects_type type objects whose geometries are sought.
        :param split_surfaces: a boolean specifying if the surfaces of each building will stay
                            splitted or be merged into one geometry

        :return: a string containing the right SQL query that should be executed.
        """
        # Because the 3DCityDB's Building table regroups both the buildings mixed
        # with their building's sub-divisions (Building is an "abstraction"
        # from which inherits concrete building class as well building-subdivisions
        # a.k.a. parts) we must first collect all the buildings and their parts:

        if split_surfaces:
            query = \
                "SELECT surface_geometry.id, ST_AsBinary(ST_Multi( " + \
                "surface_geometry.geometry)), " + \
                "objectclass.classname " + \
                "FROM citydb.surface_geometry JOIN citydb.thematic_surface " + \
                "ON surface_geometry.root_id=thematic_surface.lod2_multi_surface_id " + \
                "JOIN citydb.building ON thematic_surface.building_id = building.id " + \
                "JOIN citydb.objectclass ON thematic_surface.objectclass_id = objectclass.id " + \
                "WHERE building.building_root_id IN " + buildings_ids_arg
        else:
            query = \
                "SELECT building.building_root_id, ST_AsBinary(ST_Multi(ST_Collect( " + \
                "surface_geometry.geometry))), " + \
                "objectclass.classname " + \
                "FROM citydb.surface_geometry JOIN citydb.thematic_surface " + \
                "ON surface_geometry.root_id=thematic_surface.lod2_multi_surface_id " + \
                "JOIN citydb.building ON thematic_surface.building_id = building.id " + \
                "JOIN citydb.objectclass ON building.objectclass_id = objectclass.id " + \
                "WHERE building.building_root_id IN " + buildings_ids_arg + " " + \
                "GROUP BY building.building_root_id, objectclass.classname"

        return query

    @staticmethod
    def sql_query_geometries_with_texture_coordinates(buildings_ids_arg):
        """
        :param buildings_ids_arg: a formatted list of (city)gml identifier corresponding to
                            objects_type type objects whose geometries are sought.
        :return: a string containing the right SQL query that should be executed.
        """
        # Because the 3DCityDB's Building table regroups both the buildings mixed
        # with their building's sub-divisions (Building is an "abstraction"
        # from which inherits concrete building class as well building-subdivisions
        # a.k.a. parts) we must first collect all the buildings and their parts:
        query = ("SELECT surface_geometry.id, "
                 "ST_AsBinary(ST_Multi(surface_geometry.geometry)) as geom , "
                 "ST_AsBinary(ST_Multi(ST_Translate(ST_Scale(textureparam.texture_coordinates, 1, -1), 0, 1))) as uvs, "
                 "tex_image_uri AS uri FROM citydb.building JOIN "
                 "citydb.thematic_surface ON building.id=thematic_surface.building_id JOIN "
                 "citydb.surface_geometry ON surface_geometry.root_id="
                 "thematic_surface.lod2_multi_surface_id JOIN citydb.textureparam ON "
                 "textureparam.surface_geometry_id=surface_geometry.id "
                 "JOIN citydb.surface_data ON textureparam.surface_data_id=surface_data.id "
                 "JOIN citydb.tex_image ON surface_data.tex_image_id=tex_image.id "
                 "WHERE building.building_root_id IN " + buildings_ids_arg)
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
            "FROM citydb.surface_geometry JOIN citydb.thematic_surface " + \
            "ON surface_geometry.root_id=thematic_surface.lod2_multi_surface_id " + \
            "JOIN citydb.building ON thematic_surface.building_id = building.id " + \
            "WHERE building.building_root_id = " + str(id) + \
            " GROUP BY building.building_root_id"

        return query

    @staticmethod
    def create_batch_table_extension(extension_name, ids=None, objects=None):
        if CityMBuildings.is_bth_set() and extension_name == "batch_table_hierarchy":
            cityobjects_ids = "("
            for i in range(0, len(ids) - 1):
                cityobjects_ids += str(ids[i]) + ','
            cityobjects_ids += str(ids[-1]) + ')'
            return create_batch_table_hierarchy(CityMCityObjects.get_cursor(), cityobjects_ids)

        if extension_name == "temporal":
            temporal_bt = TemporalBatchTable()

            for building in objects:
                temporal_bt.append_feature_id(building.get_temporal_id())
                temporal_bt.append_start_date(building.get_start_date())
                temporal_bt.append_end_date(building.get_end_date())
            return temporal_bt

        return None

    @staticmethod
    def create_bounding_volume_extension(extension_name, ids=None, objects=None):
        if extension_name == "temporal":
            temporal_bv = TemporalBoundingVolume()
            bounding_dates = temporal_extract_bounding_dates(objects)
            temporal_bv.set_start_date(bounding_dates['start_date'])
            temporal_bv.set_end_date(bounding_dates['end_date'])
            return temporal_bv
        return None
