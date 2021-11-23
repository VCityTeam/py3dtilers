from .geojson import Geojson


class GeojsonPolygon(Geojson):

    def __init__(self, id=None, feature_properties=None, feature_geometry=None, is_multi_geom=False):
        super().__init__(id, feature_properties, feature_geometry)

        self.is_multi_geom = is_multi_geom

    def parse_geojson(self, properties, is_roof=False):
        super().parse_geojson(properties, is_roof)

        if self.is_multi_geom:
            coords = self.feature_geometry['coordinates'][0][0][:-1]
        else:
            coords = self.feature_geometry['coordinates'][0][:-1]
        if is_roof:
            for coord in coords:
                coord[2] -= self.height
        self.polygon = coords

        return True
