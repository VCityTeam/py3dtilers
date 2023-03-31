# -*- coding: utf-8 -*-
from io import BytesIO
from py3dtiles import TriangleSoup
import os

from ..Common import Feature, FeatureList
from ..Texture import Texture


class CityMCityObject(Feature):
    """
    The base class of all thematic classes within CityGML’s data model is the abstract class
    _CityObject. (cf 3DCityDB Version 3.3.0 Documentation).
    """

    def __init__(self, database_id=None, gml_id=None):
        super().__init__(database_id)
        self.set_gml_id(gml_id)
        self.texture_uri = None

    def get_database_id(self):
        """
        Return the database id of this object. The id from the database is used as the main id.
        :return: the id of the object
        """
        return super().get_id()

    def set_database_id(self, id):
        """
        Set the database id of this object. The id from the database is used as the main id.
        :param id: the id
        """
        super().set_id(id)

    def set_gml_id(self, gml_id):
        """
        Set the gml id of this object. The gml id is kept into the batch table.
        :param gml_id: the id of the object
        """
        super().add_batchtable_data('gml_id', gml_id)

    def get_gml_id(self):
        """
        :return: the (city)gml identifier of an object that should be encountered
                in the database.
        """
        return super().get_batchtable_data()['gml_id']

    def has_texture(self):
        """
        Return True if the feature has a texture URI.
        :return: a boolean
        """
        return self.texture_uri is not None

    def get_geom(self, user_arguments=None, feature_list=None, material_indexes=dict()):
        """
        Set the geometry of the feature.
        :return: a list of Feature
        """
        id = '(' + str(self.get_database_id()) + ')'
        cursor = self.objects_type.get_cursor()
        cityobjects_with_geom = list()
        if user_arguments.with_texture:
            cursor.execute(self.objects_type.sql_query_geometries_with_texture_coordinates(id))
        else:
            cursor.execute(self.objects_type.sql_query_geometries(id, user_arguments.split_surfaces))
        for t in cursor.fetchall():
            try:
                feature_id = t[0]
                geom_as_string = t[1]
                if geom_as_string is not None:
                    cityobject = self.__class__(feature_id, self.get_gml_id())
                    associated_data = []

                    if user_arguments.with_texture:
                        uv_as_string = t[2]
                        texture_uri = t[3]
                        cityobject.texture_uri = texture_uri
                        associated_data = [uv_as_string]
                    else:
                        surface_classname = t[2]
                        cityobject.add_batchtable_data('citygml::surface_type', surface_classname)
                        if user_arguments.add_color:
                            if surface_classname not in material_indexes:
                                material = feature_list.get_color_config().get_color_by_key(surface_classname)
                                material_indexes[surface_classname] = len(feature_list.materials)
                                feature_list.add_materials([material])
                            cityobject.material_index = material_indexes[surface_classname]

                    cityobject.geom = TriangleSoup.from_wkb_multipolygon(geom_as_string, associated_data)
                    if len(cityobject.geom.triangles[0]) > 0:
                        cityobject.set_box()
                        cityobject.centroid = self.centroid
                        cityobjects_with_geom.append(cityobject)
            except Exception:
                continue
        return cityobjects_with_geom


class CityMCityObjects(FeatureList):
    """
    A decorated list of CityMCityObject type objects.
    """

    object_type = CityMCityObject

    gml_cursor = None

    def __init__(self, cityMCityObjects=None):
        if self.color_config is None:
            config_path = os.path.join(os.path.dirname(__file__), "..", "Color", "citytiler_config.json")
            self.set_color_config(config_path)
        super().__init__(cityMCityObjects)

    def get_textures(self):
        """
        Return a dictionary of all the textures where the keys are the IDs of the features.
        :return: a dictionary of textures
        """
        texture_dict = dict()
        uri_dict = dict()
        for feature in self.get_features():
            uri = feature.texture_uri
            if uri not in uri_dict:
                stream = self.get_image_from_binary(uri, self.__class__, CityMCityObjects.gml_cursor)
                uri_dict[uri] = Texture(stream)
            texture_dict[feature.get_id()] = uri_dict[uri].get_cropped_texture_image(feature.geom.triangles[1])
        return texture_dict

    def filter(self, filter_function):
        """
        Filter the features. Keep only those accepted by the filter function.
        The filter function must take an ID as input.
        :param filter_function: a function
        """
        self.features = list(filter(lambda f: filter_function(f.get_gml_id()), self.features))

    @staticmethod
    def set_cursor(cursor):
        """
        Set the CityMCityObjects cursor to the current cursor to be able to execute queries in the database.
        :param cursor: the cursor of the current database
        """
        CityMCityObjects.gml_cursor = cursor

    @staticmethod
    def get_cursor():
        """
        Return the current cursor to be able to execute queries in the database.
        :return: the cursor of the current database
        """
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
            object_type = objects_type.object_type
        else:
            # We need to deal with the fact that the answer will (generically)
            # not preserve the order of the objects that was given to the query
            objects_with_gmlid_key = dict()
            for cityobject in cityobjects:
                objects_with_gmlid_key[cityobject.get_gml_id()] = cityobject

        for obj in cursor.fetchall():
            object_id = obj[0]
            gml_id = obj[1]
            if no_input:
                new_object = object_type(object_id, gml_id)
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
    def sql_query_textures(image_uri):
        """
        :param image_uri: a string which is the uri of the texture to select in the database
        :return: a string containing the right SQL query that should be executed.
        """

        query = \
            "SELECT tex_image_data FROM citydb.tex_image WHERE tex_image_uri = '" + image_uri + "' "
        return query

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
        return res

    @staticmethod
    def get_image_from_binary(textureUri, objects_type, cursor):
        """
        Return the texture image as a byte stream.
        :param textureUri: the URI of the texture image.
        :param objects_type: a class name among CityMCityObject derived classes.
        :param cursor: a database access cursor
        :return: an image as bytes
        """
        imageBinaryData = objects_type.retrieve_textures(
            cursor,
            textureUri,
            objects_type)
        LEFT_THUMB = imageBinaryData[0][0]
        stream = BytesIO(LEFT_THUMB)
        return stream

    @staticmethod
    def sql_query_centroid():
        """
        Virtual method: all CityMCityObjects and childs classes instances should
        implement this method.

        :return: no return value.
        """
        pass

    @staticmethod
    def sql_query_geometries_with_texture_coordinates():
        """
        Virtual method: all CityMCityObjects and childs classes instances should
        implement this method.

        :return: no return value.
        """
        pass
