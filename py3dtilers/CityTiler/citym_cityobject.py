# -*- coding: utf-8 -*-
import sys

from ..Common import ObjectToTile, ObjectsToTile


class CityMCityObject(ObjectToTile):
    """
    The base class of all thematic classes within CityGML’s data model is the abstract class
    _CityObject. (cf 3DCityDB Version 3.3.0 Documentation).
    """

    def __init__(self, database_id=None, gml_id=None):
        super().__init__(database_id)
        self.set_gml_id(gml_id)

    def get_database_id(self):
        return super().get_id()

    def set_database_id(self, id):
        return super().set_id(id)

    def set_gml_id(self, gml_id):
        return super().set_alt_id(gml_id)

    def get_gml_id(self):
        """
        :return: the (city)gml identifier of an object that should be encountered
                in the database.
        """
        return super().get_alt_id()


class CityMCityObjects(ObjectsToTile):
    """
    A decorated list of CityMCityObject type objects.
    """

    gml_cursor = None

    def __init__(self, cityMCityObjects=None):
        super().__init__(cityMCityObjects)

    @staticmethod
    def set_cursor(cursor):
        CityMCityObjects.gml_cursor = cursor

    @staticmethod
    def get_cursor():
        return CityMCityObjects.gml_cursor

    @staticmethod
    def sql_query_objects():
        """
        Virtual method: all CityMCityObjects and childs classes instances should
        implement this method.

        :return: no return value.
        """
        pass

    @staticmethod
    def retrieve_objects(cursor, objects_type, cityobjects=list()):
        """
        :param cursor: a database access cursor.
        :param objects_type: a class name among CityMCityObject derived classes.
                        For example, objects_type can be "CityMBuilding".

        :param cityobjects: a list of objects_type type object that should be
                        sought in the database. When this list is empty all
                        the objects encountered in the database are returned.

        :return: an objects_type type object containing the objects that were retrieved
                in the 3DCityDB database, each object being decorated with its database
                identifier as well as its 3D bounding box (as retrieved in the database).
        """
        if not cityobjects:
            no_input = True
        else:
            no_input = False
        cursor.execute(objects_type.sql_query_objects(cityobjects))

        if no_input:
            result_objects = objects_type()
        else:
            # We need to deal with the fact that the answer will (generically)
            # not preserve the order of the objects that was given to the query
            objects_with_gmlid_key = dict()
            for cityobject in cityobjects:
                objects_with_gmlid_key[cityobject.gml_id] = cityobject

        for t in cursor.fetchall():
            object_id = t[0]
            if not t[1]:
                print("Warning: object with id ", object_id)
                print("         has no 'cityobject.envelope'.")
                if no_input:
                    print("     Dropping this object (downstream trouble ?)")
                    continue
                print("     Exiting (is the database corrupted ?)")
                sys.exit(1)
            gml_id = t[2]
            if no_input:
                new_object = CityMCityObject(object_id, gml_id=gml_id)
                result_objects.append(new_object)
            else:
                cityobject = objects_with_gmlid_key[gml_id]
                cityobject.set_database_id(object_id)
                cityobject.set_gml_id(gml_id)
        if no_input:
            return result_objects
        else:
            return cityobjects

    @staticmethod
    def sql_query_geometries():
        """
        Virtual method: all CityMCityObjects and childs classes instances should
        implement this method.

        :return: no return value.
        """
        pass

    @staticmethod
    def retrieve_textures(cursor, image_uri, objects_type):
        """
        :param cursor: a database access cursor
        :param image_uri: the uri (as string) of the texture to select in the database
        :param objects_type: a class name among CityMCityObject derived classes.
                        For example, objects_type can be "CityMBuilding".
        :rtype List: the binary data of the texture image
        """
        res = []
        cursor.execute(objects_type.sql_query_textures(image_uri))
        for t in cursor.fetchall():
            res.append(t)
        return(res)
