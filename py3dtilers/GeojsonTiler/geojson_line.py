from .geojson import Geojson
from .lineBuffer import LineBuffer


class GeojsonLine(Geojson):
    """
    The Python representation of a GeoJSON line or multiline feature.
    A GeojsonLine instance has a geometry and properties.
    """

    # Default width will be used if no width is found when parsing LineString or MultiLineString
    default_width = 2

    def __init__(self, id=None, feature_properties=None, feature_geometry=None, is_multi_geom=False):
        super().__init__(id, feature_properties, feature_geometry)

        self.width = 0
        """The width of the buffer when parsing LineString or MultiLineString"""

        self.is_multi_geom = is_multi_geom
        self.custom_triangulation = True

    def parse_geojson(self, properties, is_roof=False, color_attribute=('NONE', 'numeric')):
        super().parse_geojson(properties, is_roof, color_attribute)

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
                print("No propertie called " + width_name + " in feature " + str(Geojson.n_feature) + ". Set width to default value (" + str(GeojsonLine.default_width) + ").")
                self.width = GeojsonLine.default_width

        if self.is_multi_geom:
            coords = self.feature_geometry['coordinates'][0]
        else:
            coords = self.feature_geometry['coordinates']

        for i in range(0, len(coords) - 1):
            if coords[i] == coords[i + 1]:
                print("Identical coordinates in feature " + str(Geojson.n_feature))
                return False

        z_name = properties[properties.index('z') + 1]
        self.set_z(coords, z_name)

        line_buffer = LineBuffer(self.width)
        self.exterior_ring = line_buffer.buffer_line_string(coords)
        self.interior_rings = []

        return True
