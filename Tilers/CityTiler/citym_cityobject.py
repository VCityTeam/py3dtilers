# -*- coding: utf-8 -*-
import sys

from py3dtiles import BoundingVolumeBox, TriangleSoup
from py3dtiles import ObjectToTile, ObjectsToTile


class CityMCityObject(ObjectToTile):
    """
    The base class of all thematic classes within CityGML’s data model is the abstract class
    _CityObject. (cf 3DCityDB Version 3.3.0 Documentation).
    """
    def __init__(self, id=None, box_in=None):
        """
        :param id: given identifier
        :param box_2D: the maximum extents of the geometry a returned by a
                       PostGis::Box3D(geometry geomA) call (refer to
                       https://postgis.net/docs/Box3D.html) that is a string
                       of the form 'BOX3D(1 2 3, 4 5 6)' where:
                        * 1, 2 and 3 are the respective minimum of X, Y and Z
                        * 4, 5 and 6 are the respective maximum of X, Y and Z
        """
        super().__init__(id)
        if box_in:
            self.set_box(box_in)

    def set_box(self, box_in):
        # Realize the following convertion:
        # 'BOX3D(1 2 3, 4 5 6)' -> [[1, 2, 3], [4, 5, 6]]
        box_parsed = [[float(coord) for coord in point.split(' ')]
                                    for point in box_in[6:-1].split(',')]
        x_min = box_parsed[0][0]
        x_max = box_parsed[1][0]
        y_min = box_parsed[0][1]
        y_max = box_parsed[1][1]
        z_min = box_parsed[0][2]
        z_max = box_parsed[1][2]

        self.box = BoundingVolumeBox()
        self.box.set_from_mins_maxs([x_min, y_min, z_min, x_max, y_max, z_max])
        # Centroid of the box
        self.centroid = [(x_min + x_max) / 2.0,
                         (y_min + y_max) / 2.0,
                         (z_min + z_max) / 2.0]

    def get_database_id(self):
        return super().get_id()
    
    def set_database_id(self):
        return super().set_id()

    def set_gml_id(self, gml_id):
        self.gml_id = gml_id

    def get_gml_id(self):
        """
        :return: the (city)gml identifier of an object that should be encountered
                in the database.
        """
        return self.gml_id

class CityMCityObjects(ObjectsToTile):
    """
    A decorated list of CityMCityObject type objects.
    """
    def __init__(self,cityMCityObjects=None):
        super().__init__(cityMCityObjects)

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
            box = t[1]
            if no_input:
                new_object = CityMCityObject(object_id, box)
                result_objects.append(new_object)
            else:
                gml_id = t[2]
                cityobject = objects_with_gmlid_key[gml_id]
                cityobject.set_id(object_id)
                cityobject.set_box(box)
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
    def retrieve_geometries(cursor, city_object_ids, offset, objects_type):
        """
        :param cursor: a database access cursor
        :param city_object_ids: a list of (city)gml identifier corresponding to
                       objects_type type objects whose geometries are sought.
        :param offset: the offset (a 3D "vector" of floats) by which the
                       geographical coordinates should be translated (the
                       computation is done at the GIS level).
        :param objects_type: a class name among CityMCityObject derived classes.
                        For example, objects_type can be "CityMBuilding".
        :rtype List[Dict]: a TileContent in the form a B3dm.
        """
        city_object_ids_arg = str(city_object_ids).replace(',)', ')')

        cursor.execute(objects_type.sql_query_geometries(offset,
                                                         city_object_ids_arg))

        # Deal with the reordering of the retrieved geometries
        city_objects_with_gmlid_key = dict()
        for t in cursor.fetchall():
            city_object_root_id = t[0]
            geom_as_string = t[1]
            if geom_as_string is None:
                # Some thematic surface may have no geometry (due to a cityGML
                # exporter bug?): simply ignore them.
                print("Warning: no valid geometry in database.")
                sys.exit(1)
            geom = TriangleSoup.from_wkb_multipolygon(geom_as_string)
            if len(geom.triangles[0]) == 0:
                print("Warning: empty (no) geometry from the database.")
                sys.exit(1)
            city_objects_with_gmlid_key[city_object_root_id] = geom

        # Package the geometries within a data structure that the
        # GlTF.from_binary_arrays() function (see below) expects to consume:
        arrays = []
        for incoming_id in city_object_ids:
            geom = city_objects_with_gmlid_key[incoming_id]
            arrays.append({
                'position': geom.getPositionArray(),
                'normal': geom.getNormalArray(),
                'bbox': [[float(i) for i in j] for j in geom.getBbox()]
            })
        return arrays
