import numpy as np
from py3dtiles import BoundingVolumeBox, TriangleSoup

from ..Color import ColorConfig


class ObjectToTile(object):
    """
    The base class of all object that need to be tiled, in order to be
    used with the corresponding tiler.
    """

    def __init__(self, id=None):
        """
        :param id: given identifier
        """

        self.geom = TriangleSoup()

        # Optional application specific data to be added to the batch table for this object
        self.batchtable_data = None

        # A Bounding Volume Box object
        self.box = None

        # The centroid of the box
        self.centroid = np.array([0, 0, 0])

        self.texture = None

        self.material_index = 0

        self.set_id(id)

    def set_id(self, id):
        self.id = id

    def get_id(self):
        return self.id

    def set_batchtable_data(self, data):
        self.batchtable_data = data

    def get_batchtable_data(self):
        return self.batchtable_data

    def get_centroid(self):
        return self.centroid

    def get_bounding_volume_box(self):
        return self.box

    def get_geom_as_triangles(self):
        return self.geom.triangles[0]

    def set_triangles(self, triangles):
        self.geom.triangles[0] = triangles

    def set_box(self):
        """
        Parameters
        ----------
        Returns
        -------
        """
        bbox = self.geom.getBbox()
        self.box = BoundingVolumeBox()
        self.box.set_from_mins_maxs(np.append(bbox[0], bbox[1]))

        # Set centroid from Bbox center
        self.centroid = np.array(self.box.get_center())

    def get_texture(self):
        return self.texture

    def set_texture(self, texture):
        self.texture = texture

    def has_texture(self):
        return self.texture is not None


class ObjectsToTile(object):
    """
    A decorated list of ObjectsToTile type objects.
    """

    # The material used by default for geometries
    default_mat = None

    def __init__(self, objects=None):
        self.objects = list()
        if ObjectsToTile.default_mat is None:
            ObjectsToTile.default_mat = ColorConfig().get_default_color()
        self.materials = [ObjectsToTile.default_mat]
        if(objects):
            self.objects.extend(objects)

    def __iter__(self):
        return iter(self.objects)

    def __getitem__(self, item):
        if isinstance(item, slice):
            objects_class = self.__class__
            return objects_class(self.objects.__getitem__(item))
        # item is then an int type:
        return self.objects.__getitem__(item)

    def __add__(self, other):
        objects_class = self.__class__
        new_objects = objects_class(self.objects)
        new_objects.objects.extend(other.objects)
        return new_objects

    def append(self, obj):
        self.objects.append(obj)

    def extend(self, others):
        self.objects.extend(others)

    def get_objects(self):
        if not self.is_list_of_objects_to_tile():
            return self.objects
        else:
            objects = list()
            for objs in self.objects:
                objects.extend(objs.get_objects())
            return objects

    def __len__(self):
        return len(self.objects)

    def is_list_of_objects_to_tile(self):
        """Check if this instance of ObjectsToTile contains others ObjectsToTile"""
        return isinstance(self.objects[0], ObjectsToTile)

    def get_centroid(self):
        """
        :param objects: an array containing objs

        :return: the centroid of the tileset.
        """
        centroid = [0., 0., 0.]
        for objectToTile in self:
            centroid += objectToTile.get_centroid()
        return np.array([centroid[0] / len(self),
                         centroid[1] / len(self),
                         centroid[2] / len(self)])

    def set_materials(self, materials):
        """
        Set the materials of this object to a new array of materials.
        :param materials: an array of GlTFMaterial
        """
        self.materials = materials

    def add_materials(self, materials):
        """
        Extend the materials of this object with another array of materials.
        :param materials: an array of GlTFMaterial
        """
        self.materials.extend(materials)

    def get_material(self, index):
        """
        Get the material at the index.
        :param index: the index (int) of the material
        """
        return self.materials[index]

    def translate_objects(self, offset):
        """
        Translate the geometries by substracting an offset
        :param offset: the Vec3 translation offset
        """
        # Translate the position of each object by an offset
        for object_to_tile in self.get_objects():
            new_geom = []
            for triangle in object_to_tile.get_geom_as_triangles():
                new_position = []
                for points in triangle:
                    # Must to do this this way to ensure that the new position
                    # stays in float32, which is mandatory for writing the GLTF
                    new_position.append(np.array(points - offset, dtype=np.float32))
                new_geom.append(new_position)
            object_to_tile.set_triangles(new_geom)
            object_to_tile.set_box()

    def change_crs(self, transformer):
        """
        Project the geometries into another CRS
        :param transformer: the transformer used to change the crs
        """
        for object_to_tile in self.get_objects():
            new_geom = []
            for triangle in object_to_tile.get_geom_as_triangles():
                new_position = []
                for point in triangle:
                    new_point = transformer.transform(point[0], point[1], point[2])
                    new_position.append(np.array(new_point, dtype=np.float32))
                new_geom.append(new_position)
            object_to_tile.set_triangles(new_geom)
            object_to_tile.set_box()

    def scale_objects(self, scale_factor):
        """
        Rescale the geometries.
        :param scale_factor: the factor to scale the objects
        """
        centroid = self.get_centroid()
        for object_to_tile in self.get_objects():
            new_geom = []
            for triangle in object_to_tile.get_geom_as_triangles():
                scaled_triangle = [((vertex - centroid) * scale_factor) + centroid for vertex in triangle]
                new_geom.append(scaled_triangle)
            object_to_tile.set_triangles(new_geom)
            object_to_tile.set_box()

    def get_textures(self):
        """
        Return a dictionary of all the textures where the keys are the IDs of the geometries.
        :return: a dictionary of textures
        """
        texture_dict = dict()
        for object_to_tile in self.get_objects():
            texture_dict[object_to_tile.get_id()] = object_to_tile.get_texture()
        return texture_dict

    @staticmethod
    def create_batch_table_extension(extension_name, ids=None, objects=None):
        pass

    @staticmethod
    def create_bounding_volume_extension(extension_name, ids=None, objects=None):
        pass
