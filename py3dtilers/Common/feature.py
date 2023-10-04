import numpy as np
from py3dtiles import BoundingVolumeBox, TriangleSoup
from typing import List
from ..Color import ColorConfig


class Feature(object):
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
        self.batchtable_data = {}

        # A Bounding Volume Box object
        self.box = None

        # The centroid of the box
        self.centroid = np.array([0, 0, 0])

        self.texture = None

        self.material_index = 0

        self.has_vertex_colors = False

        self.set_id(id)

    def set_id(self, id):
        """
        Set the id of this feature.
        :param id: an id
        """
        self.id = id

    def get_id(self):
        """
        Return the id of the feature.
        """
        return self.id

    def set_batchtable_data(self, data):
        """
        Set the batch table data associed to this feature.
        :param data: a dictionary
        """
        self.batchtable_data = data

    def get_batchtable_data(self):
        """
        Return the batch table data associed to this feature.
        :return: a dictionary
        """
        return self.batchtable_data

    def add_batchtable_data(self, key, data):
        """
        Add an attribute to the batch table data of this feature.
        :param key: the name of the attribute
        :param data: the data
        """
        self.batchtable_data[key] = data

    def get_centroid(self):
        """
        Return the centroid of this feature.
        :return: a 3D point as np array
        """
        return self.centroid

    def get_bounding_volume_box(self):
        """
        Return the BoundingVolumeBox of this feature.
        :return: a BoundingVolumeBox
        """
        return self.box

    def get_geom_as_triangles(self):
        """
        Return the triangles of this feature.
        :return: a list of triangles
        """
        return self.geom.triangles[0]

    def set_triangles(self, triangles):
        """
        Set the triangles of this feature.
        :param triangles: a list of triangles.
        """
        self.geom.triangles[0] = triangles

    def set_box(self):
        """
        Set the BoundingVolumeBox of this feature from its triangles.
        Also set the centroid.
        """
        bbox = self.geom.getBbox()
        self.box = BoundingVolumeBox()
        self.box.set_from_mins_maxs(np.append(bbox[0], bbox[1]))

        # Set centroid from Bbox center
        self.centroid = np.array(self.box.get_center())

    def get_texture(self):
        """
        Return the texture image of this feature.
        :return: a Pillow image
        """
        return self.texture

    def set_texture(self, texture):
        """
        Set the texture image of this feature.
        :param texture: a Pillow image
        """
        self.texture = texture

    def has_texture(self):
        """
        Check if the feature has a texture.
        :return: a boolean
        """
        return self.texture is not None

    def get_geom(self, user_arguments=None, feature_list=None, material_indexes=dict()):
        """
        Get the geometry of the feature.
        :return: a boolean
        """
        if self.geom is not None and len(self.geom.triangles) > 0 and len(self.get_geom_as_triangles()) > 0:
            return [self]
        else:
            return []


class FeatureList(object):
    """
    A decorated list of Feature instances.
    """

    # The color config used to create colored materials
    color_config = None
    # The material used by default for geometries
    default_mat = None

    def __init__(self, features: List[Feature] = None):
        self.features = list()
        if FeatureList.default_mat is None:
            FeatureList.default_mat = self.get_color_config().get_default_color()
        self.materials = [FeatureList.default_mat]
        if features:
            self.features.extend(features)

    def __iter__(self):
        return iter(self.features)

    def __getitem__(self, item):
        if isinstance(item, slice):
            features_class = self.__class__
            return features_class(self.features.__getitem__(item))
        # item is then an int type:
        return self.features.__getitem__(item)

    def __add__(self, other: 'FeatureList'):
        features_class = self.__class__
        new_features = features_class(self.features)
        new_features.features.extend(other.features)
        return new_features

    def append(self, feature: Feature):
        self.features.append(feature)

    def extend(self, others: 'FeatureList'):
        self.features.extend(others)

    def get_features(self):
        """
        Return (recursively) all the features in this FeatureList.
        :return: a list of Feature instances
        """
        if not self.is_list_of_feature_list():
            return self.features
        else:
            features = list()
            for objs in self.features:
                features.extend(objs.get_features())
            return features

    def set_features(self, features: List[Feature]):
        """
        Set the list of features.
        :param features: a list of Feature
        """
        self.features = features

    def delete_features_ref(self):
        """Delete the reference to the features contained by this instance, so the features are destroyed when unused."""
        del self.features

    def __len__(self):
        return len(self.features)

    def is_list_of_feature_list(self):
        """Check if this instance of FeatureList contains others FeatureList"""
        return isinstance(self.features[0], FeatureList)

    def get_centroid(self):
        """
        Return the centroid of the FeatureList.
        The centroid is the average of the centroids of all the features.
        :return: an array
        """
        centroid = [0., 0., 0.]
        for feature in self:
            centroid += feature.get_centroid()
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

    def add_material(self, material):
        """
        Extend the materials of this object with a GltF material.
        :param material: a GlTFMaterial
        """
        self.materials.append(material)

    def get_material(self, index):
        """
        Get the material at the index.
        :param index: the index (int) of the material
        :return: a glTF material
        """
        return self.materials[index]

    def is_material_registered(self, material):
        """
        Check if a material is already set in materials array
        :param material: a GlTFMaterial
        :return: bool
        """
        for mat in self.materials:
            if (mat.rgba == material.rgba).all():
                return True
        return False

    def get_material_index(self, material):
        """
        Get the index of a given material.
        Add it to the materials array if it is not found
        :param material: a GlTFMaterial
        :return: an index as int
        """
        i = 0
        for mat in self.materials:
            if (mat.rgba == material.rgba).all():
                return i
            i = i + 1
        self.add_material(material)
        return i

    def translate_features(self, offset):
        """
        Translate the features by adding an offset
        :param offset: the Vec3 translation offset
        """
        # Translate the position of each object by an offset
        for feature in self.get_features():
            new_geom = []
            for triangle in feature.get_geom_as_triangles():
                new_position = []
                for points in triangle:
                    new_position.append(np.array(points + offset))
                new_geom.append(new_position)
            feature.set_triangles(new_geom)
            feature.set_box()

    def change_crs(self, transformer, offset=np.array([0, 0, 0])):
        """
        Project the features into another CRS
        :param transformer: the transformer used to change the crs
        """
        for feature in self.get_features():
            new_geom = []
            for triangle in feature.get_geom_as_triangles():
                new_position = []
                for point in triangle:
                    new_point = transformer.transform((point + offset)[0], (point + offset)[1], (point + offset)[2])
                    new_position.append(np.array(new_point))
                new_geom.append(new_position)
            feature.set_triangles(new_geom)
            feature.set_box()

    def height_mult_features(self, height_mult):
        """
        Converts height to different units by specifing the multiplier
        :param height_mult: the factor to scale height values
        """
        for feature in self.get_features():
            new_geom = []
            for triangle in feature.get_geom_as_triangles():
                scaled_triangle = []
                for vertex in triangle:
                    scaled_vertex = np.array([vertex[0], vertex[1], vertex[2] * height_mult])
                    scaled_triangle.append(scaled_vertex)
                new_geom.append(scaled_triangle)
            feature.set_triangles(new_geom)
            feature.set_box()

    def scale_features(self, scale_factor, centroid):
        """
        Rescale the features.
        :param scale_factor: the factor to scale the objects
        :param centroid: the centroid used as reference point
        """
        for feature in self.get_features():
            new_geom = []
            for triangle in feature.get_geom_as_triangles():
                scaled_triangle = [((vertex - centroid) * scale_factor) + centroid for vertex in triangle]
                new_geom.append(scaled_triangle)
            feature.set_triangles(new_geom)
            feature.set_box()

    def get_textures(self):
        """
        Return a dictionary of all the textures where the keys are the IDs of the features.
        :return: a dictionary of textures
        """
        texture_dict = dict()
        for feature in self.get_features():
            texture_dict[feature.get_id()] = feature.get_texture()
        return texture_dict

    def set_features_geom(self, user_arguments=None):
        """
        Set the geometry of the features.
        Keep only the features with geometry.
        """
        features_with_geom = list()
        material_indexes = dict()
        for feature in self.features:
            features_with_geom.extend(feature.get_geom(user_arguments, self, material_indexes))
        self.set_features(features_with_geom)

    def filter(self, filter_function):
        """
        Filter the features. Keep only those accepted by the filter function.
        The filter function must take an ID as input.
        :param filter_function: a function
        """
        self.features = list(filter(lambda f: filter_function(f.get_id()), self.features))

    @classmethod
    def set_color_config(cls, config_path):
        """
        Set the ColorConfig from a JSON file.
        The ColorConfig is used to created colored materials.
        :param config_path: path to the JSON file
        """
        FeatureList.color_config = ColorConfig(config_path)

    @classmethod
    def get_color_config(cls):
        """
        Return the ColorConfig used to created colored materials.
        :return: a ColorConfig
        """
        if FeatureList.color_config is None:
            FeatureList.color_config = ColorConfig()
        return FeatureList.color_config

    @staticmethod
    def create_batch_table_extension(extension_name, ids=None, features=None):
        """Virtual method to create a batch table extension."""
        pass

    @staticmethod
    def create_bounding_volume_extension(extension_name, ids=None, features=None):
        """Virtual method to create a bounding volume box extension."""
        pass
