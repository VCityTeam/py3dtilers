from shapely.geometry import LinearRing
from .geojson import Geojson


class GeojsonPolygon(Geojson):

    def __init__(self, id=None, feature_properties=None, feature_geometry=None, is_multi_geom=False):
        super().__init__(id, feature_properties, feature_geometry)

        self.is_multi_geom = is_multi_geom

    def parse_geojson(self, properties, is_roof=False, color_attribute=('NONE', 'numeric')):
        super().parse_geojson(properties, is_roof, color_attribute)

        if self.is_multi_geom:
            coords = self.get_clockwise_polygon(self.feature_geometry['coordinates'][0][0])
        else:
            coords = self.get_clockwise_polygon(self.feature_geometry['coordinates'][0])
        if is_roof:
            for coord in coords:
                coord[2] -= self.height
        self.polygon = coords

        z_name = properties[properties.index('z') + 1]
        self.set_z(coords, z_name)

        return True

    def get_clockwise_polygon(self, polygon):
        """
        Return a clockwise polygon without the last point (the last point is the same as the first one).
        :return: a list of points
        """
        if LinearRing(polygon).is_ccw:
            return polygon[:-1][::-1]
        else:
            return polygon[:-1]
