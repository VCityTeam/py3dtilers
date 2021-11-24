from .geojson import Geojson
from .lineBuffer import LineBuffer


class GeojsonLine(Geojson):

    # Default width will be used if no width is found when parsing LineString or MultiLineString
    default_width = 2

    def __init__(self, id=None, feature_properties=None, feature_geometry=None, is_multi_geom=False):
        super().__init__(id, feature_properties, feature_geometry)

        self.width = 0
        """The width of the buffer when parsing LineString or MultiLineString"""

        self.is_multi_geom = is_multi_geom
        self.custom_triangulation = True

    def parse_geojson(self, properties, is_roof=False):
        super().parse_geojson(properties, is_roof)

        width_name = properties[properties.index('width') + 1]
        if width_name.replace('.', '', 1).isdigit():
            self.width = float(width_name)
        else:
            if width_name in self.feature_properties:
                if self.feature_properties[width_name] is not None and self.feature_properties[width_name] > 0:
                    self.width = self.feature_properties[width_name]
                else:
                    self.width = GeojsonLine.default_width
            else:
                print("No propertie called " + width_name + " in feature " + str(Geojson.n_feature) + ". Set width to default value (" + str(Geojson.default_width) + ").")
                self.width = GeojsonLine.default_width

        if self.is_multi_geom:
            coords = self.feature_geometry['coordinates'][0]
        else:
            coords = self.feature_geometry['coordinates']

        line_buffer = LineBuffer(self.width)
        self.polygon = line_buffer.buffer_line_string(coords)

        return True
