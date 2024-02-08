from shapely.geometry import LinearRing
from .geojson import Geojson


class GeojsonPolygon(Geojson):
    """
    The Python representation of a GeoJSON polygon or multipolygon feature.
    A GeojsonPolygon instance has a geometry and properties.
    """

    def __init__(self, id=None, feature_properties=None, feature_geometry=None, is_multi_geom=False):
        super().__init__(id, feature_properties, feature_geometry)

        self.is_multi_geom = is_multi_geom

    def parse_geojson(self, properties, is_roof=False, color_attribute=('NONE', 'numeric')):
        super().parse_geojson(properties, is_roof, color_attribute)

        if self.is_multi_geom:
            exterior_ring = self.get_clockwise_polygon(
                self.feature_geometry["coordinates"][0][0]
            )
            interior_rings = [
                int_ring[:-1]
                for int_ring in self.feature_geometry["coordinates"][0][1:]
            ]
        else:
            exterior_ring = self.get_clockwise_polygon(
                self.feature_geometry["coordinates"][0]
            )
            interior_rings = [
                int_ring[:-1]
                for int_ring in self.feature_geometry["coordinates"][1:]
            ]

        if is_roof:
            for coord in exterior_ring:
                coord[2] -= self.height
            for coord in interior_rings:
                coord[2] -= self.height

        self.exterior_ring = exterior_ring
        self.interior_rings = interior_rings

        z_name = properties[properties.index("z") + 1]
        self.set_z(exterior_ring, z_name)
        for int_ring in interior_rings:
            self.set_z(int_ring, z_name)

        return True

    def get_clockwise_polygon(self, polygon):
    
        """
        Return a clockwise polygon without the last point (the last point is the same as the first one).

        :param polygon: a list of points
        :return: a list of points
        """
        if LinearRing(polygon).is_ccw:
            return polygon[:-1][::-1]
        else:
            return polygon[:-1]
