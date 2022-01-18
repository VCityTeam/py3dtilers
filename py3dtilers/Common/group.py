import os
from os import listdir
import json
from shapely.geometry import Point, Polygon
from ..Common import ObjectsToTile
from ..Common import kd_tree


class Group():
    """
    Contains an instance of ObjectsToTile
    It can also contain additional polygon points (used to create LOA nodes)
    """

    def __init__(self, objects_to_tile, with_polygon=False, additional_points=list(), points_dict=dict()):
        self.objects_to_tile = objects_to_tile
        self.with_polygon = with_polygon
        self.additional_points = additional_points
        self.points_dict = points_dict

    def get_centroid(self):
        """
        Get the centroid of the group.
        :return: a 3D point ([x, y, z])
        """
        return self.objects_to_tile.get_centroid()

    def round_coordinates(self, coordinates, base):
        """
        Round the coordinates to the closer multiple of a base.
        :param coordinates: a 3D point ([x, y, z])
        :param int base: the base used to round the coordinates

        :return: a 3D point rounded to the closer multiples of the base
        """
        rounded_coord = coordinates
        for i in range(0, len(coordinates)):
            rounded_coord[i] = base * round(coordinates[i] / base)
        return rounded_coord

    def add_materials(self, materials):
        """
        Keep only the materials used by the objects of this group,
        among all the materials created, and add them to the geometries.
        :param materials: an array of all the materials
        """
        seen_mat_indexes = dict()
        group_materials = []
        for feature in self.objects_to_tile:
            mat_index = feature.material_index
            if mat_index not in seen_mat_indexes:
                seen_mat_indexes[mat_index] = len(group_materials)
                group_materials.append(materials[mat_index])
            feature.material_index = seen_mat_indexes[mat_index]
        self.objects_to_tile.set_materials(group_materials)


class Groups():
    """
    Contains a list of Group
    """

    def __init__(self, objects_to_tile, polygons_path=None):
        """
        Distribute the geometries contained in objects_to_tile into different Group
        The way to distribute the geometries depends on the parameters
        :param objects_to_tile: an instance of ObjectsToTile containing a list of geometries to distribute into Group
        :param polygons_path: the path to a folder containing polygons as .geojson files.
        When this param is not None, it means we want to group geometries by polygons
        """
        self.objects_to_tile = objects_to_tile
        self.materials = objects_to_tile.materials
        if objects_to_tile.is_list_of_objects_to_tile():
            self.group_objects_by_instance()
        elif polygons_path is not None:
            self.group_objects_by_polygons(polygons_path)
        else:
            self.group_objects_with_kdtree()
        self.set_materials(self.materials)

    def get_groups_as_list(self):
        """
        Return the groups as a list.
        :return: the groups as list
        """
        return self.groups

    def set_materials(self, materials):
        """
        Set the materials of each group.
        :param materials: an array of all the materials
        """
        for group in self.groups:
            group.add_materials(materials)

    def group_objects_by_instance(self):
        """
        Create groups of geometries. One group is created per object in the ObjectsToTile. 
        """
        groups = list()
        for objects in self.objects_to_tile:
            group = Group(objects)
            groups.append(group)
        self.groups = groups

    def group_objects_with_kdtree(self):
        """
        Create groups of geometries. The geometries are distributed into groups of (max) 500 objects.
        The distribution depends on the centroid of each geometry.
        """
        groups = list()
        objects = kd_tree(self.objects_to_tile, 500)
        for objects_to_tile in objects:
            group = Group(objects_to_tile)
            groups.append(group)
        self.groups = groups

    def group_objects_by_polygons(self, polygons_path):
        """
        Load the polygons from the files in the folder
        :param polygons_path: the path to the file(s) containing polygons
        """
        polygons = list()
        files = []

        if(os.path.isdir(polygons_path)):
            geojson_dir = listdir(polygons_path)
            for geojson_file in geojson_dir:
                file_path = os.path.join(polygons_path, geojson_file)
                if(os.path.isfile(file_path)):
                    files.append(file_path)
        else:
            files.append(polygons_path)

        # Read all the polygons in the file(s)
        for file in files:
            if(".geojson" in file or ".json" in file):
                with open(file) as f:
                    gjContent = json.load(f)
                for feature in gjContent['features']:
                    if feature['geometry']['type'] == 'Polygon':
                        coords = feature['geometry']['coordinates'][0][:-1]
                    if feature['geometry']['type'] == 'MultiPolygon':
                        coords = feature['geometry']['coordinates'][0][0][:-1]
                    polygons.append(Polygon(coords))
        self.groups = self.distribute_objects_in_polygons(polygons)

    def distribute_objects_in_polygons(self, polygons):
        """
        Distribute the geometries in the polygons.
        The geometries in the same polygon are grouped together. The Group created will also contain the points of the polygon.
        If a geometry is not in any polygon, create a Group containing only this geometry. This group won't have addtional points.
        :param polygons: a list of Shapely polygons
        """

        objects_to_tile = self.objects_to_tile
        objects_to_tile_dict = {}
        objects_to_tile_without_poly = {}

        # For each geometry, find the polygon containing it
        for i, object_to_tile in enumerate(objects_to_tile):
            p = Point(object_to_tile.get_centroid())
            in_polygon = False
            for index, polygon in enumerate(polygons):
                if p.within(polygon):
                    if index in objects_to_tile_dict:
                        objects_to_tile_dict[index].append(i)
                    else:
                        objects_to_tile_dict[index] = [i]
                    in_polygon = True
                    break
            if not in_polygon:
                objects_to_tile_without_poly[i] = [i]

        # Create a list of Group
        groups = list()
        for key in objects_to_tile_dict:
            additional_points = polygons[key].exterior.coords[:-1]
            contained_objects = ObjectsToTile([objects_to_tile[i] for i in objects_to_tile_dict[key]])
            group = Group(contained_objects, with_polygon=True, additional_points=additional_points)
            groups.append(group)
        for key in objects_to_tile_without_poly:
            contained_objects = ObjectsToTile([objects_to_tile[i] for i in objects_to_tile_without_poly[key]])
            group = Group(contained_objects)
            groups.append(group)

        return self.distribute_groups_in_cubes(groups, 300)

    def distribute_groups_in_cubes(self, groups, cube_size=300):
        """
        Merges together the groups in order to reduce the number of tiles.
        The groups are distributed into cubes of a grid. The groups in the same cube are merged together.
        To avoid conflicts, the groups with a polygon are not merged with those without polygon.
        :param groups: the groups to distribute into cubes
        :param cube_size: the size of the cubes

        :return: merged groups 
        """
        groups_dict = {}

        # Create a dictionary key: cubes center (x,y,z), with geometry (boolean); value: list of groups index
        for i in range(0, len(groups)):
            closest_cube = groups[i].round_coordinates(groups[i].get_centroid(), cube_size)
            with_polygon = groups[i].with_polygon
            if (tuple(closest_cube), with_polygon) in groups_dict:
                groups_dict[(tuple(closest_cube), with_polygon)].append(i)
            else:
                groups_dict[(tuple(closest_cube), with_polygon)] = [i]

        # Merge the groups in the same cube and create new groups
        groups_in_cube = list()
        for cube in groups_dict:
            with_polygon = cube[1]
            groups_in_cube.append(self.merge_groups_together(groups, groups_dict[cube], with_polygon))

        return groups_in_cube

    def merge_groups_together(self, groups, group_indexes, with_polygon):
        """
        Creates a Group from a list of Groups
        :param groups: all the groups
        :param group_indexes: the indexes of the groups to merge together
        :param Boolean with_polygon: when creating LOA (with_polygon=True), add the polygons to the new group

        :return: a new group containing the geometries of all the groups
        """

        objects = list()
        additional_points_list = list()
        additional_points_dict = dict()

        for index in group_indexes:
            if with_polygon:
                additional_points_list.append(groups[index].additional_points)
                points_index = len(additional_points_list) - 1
                additional_points_dict[points_index] = []
                for object_to_tile in groups[index].objects_to_tile:
                    objects.append(object_to_tile)
                    additional_points_dict[points_index].append(len(objects) - 1)
            else:
                for object_to_tile in groups[index].objects_to_tile:
                    objects.append(object_to_tile)
        return Group(ObjectsToTile(objects), with_polygon=with_polygon, additional_points=additional_points_list, points_dict=additional_points_dict)
