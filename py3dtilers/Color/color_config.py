import string
import json
import os
from py3dtiles import GlTFMaterial


class ColorConfig():
    """
    A ColorConfig contains the color codes used to create colored materials.
    The color codes can be loaded from a JSON file.
    """

    default_color = [1, 1, 1]

    min_color = [0, 1, 0]
    max_color = [1, 0, 0]
    nb_colors = 20

    color_dict = {
        'default': [1, 1, 1]
    }

    def __init__(self, config_path=os.path.join(os.path.dirname(__file__), "default_config.json")):
        if config_path is not None:
            try:
                with open(config_path) as f:
                    content = json.load(f)
                self.default_color = content['default_color'] if 'default_color' in content else self.default_color
                self.min_color = content['min_color'] if 'min_color' in content else self.min_color
                self.max_color = content['max_color'] if 'max_color' in content else self.max_color
                self.nb_colors = content['nb_colors'] if 'nb_colors' in content else self.nb_colors
                self.color_dict = content['color_dict'] if 'color_dict' in content else self.color_dict
            except FileNotFoundError:
                print("The config file", config_path, "wasn't found.")
        self.min_color_code = self.to_material(self.min_color).rgba[:3]
        self.max_color_code = self.to_material(self.max_color).rgba[:3]

    def to_material(self, color):
        """
        Create a GlTFMaterial from a color code.
        :param color: a color code (rgb or hexa)

        :return: a GlTFMaterial
        """
        if isinstance(color, list):
            return GlTFMaterial(rgb=color)
        elif all(c in string.hexdigits for c in color.replace('#', '').replace('0x', '')):
            return GlTFMaterial.from_hexa(color)
        else:
            return GlTFMaterial()

    def get_color_by_key(self, key):
        """
        Get the color corresponding to the key.
        :param key: the key in the color dictionary

        :return: a GlTFMaterial
        """
        if key in self.color_dict:
            return self.to_material(self.color_dict[key])
        elif 'default' in self.color_dict:
            return self.to_material(self.color_dict['default'])
        else:
            self.get_default_color()

    def get_color_by_lerp(self, factor=0):
        """
        Get a color by interpolation between two colors (min and max colors).
        :param float factor: the lerp factor

        :return: a GlTFMaterial
        """
        return self.to_material([(max - min) * factor + min for min, max in zip(self.min_color_code, self.max_color_code)])

    def get_default_color(self):
        """
        Get the default color.
        :return: a GlTFMaterial
        """
        return self.to_material(self.default_color)
