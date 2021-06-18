import os
from os import listdir
import sys
import json
from shapely.geometry import Point, Polygon
import numpy as np
from ..Common import ObjectToTile, ObjectsToTile, ObjectsToTileWithGeometry
from ..Common import get_lod1

def create_loa(objects_to_tile, loa_path):
    return group_features_by_polygons(objects_to_tile,loa_path)

def group_features_by_polygons(features, path):
    try:
        polygon_dir = listdir(path)
    except FileNotFoundError:
        print("No directory called ", path, ". Please, place the polygons to read in", path)
        print("Exiting")
        sys.exit(1)
    polygons = list()
    for polygon_file in polygon_dir:
        if(".geojson" in polygon_file or ".json" in polygon_file):
            with open(os.path.join(path, polygon_file)) as f:
                gjContent = json.load(f)
            for feature in gjContent['features']:
                coords = feature['geometry']['coordinates'][0][:-1]
                polygons.append(Polygon(coords))
    return distribute_features_in_polygons(features, polygons)

def create_loa_from_features(features, features_indexes, index, with_geometry):
    contained_features = [features[i] for i in features_indexes]
    if with_geometry:
        loa_geometry = ObjectToTile("group" + str(index))
        for i in features_indexes:
            loa_geometry.geom.triangles.append(features[i].geom.triangles[0])
        loa_geometry = get_lod1(loa_geometry)
    else:
        loa_geometry = None
    return ObjectsToTileWithGeometry(ObjectsToTile(contained_features), loa_geometry)

def distribute_features_in_polygons(features, polygons):
    features_dict = {}
    features_without_poly = {}
    for i, feature in enumerate(features):
        p = Point(feature.get_centroid())
        in_polygon = False
        for index, polygon in enumerate(polygons):
            if p.within(polygon):
                if index in features_dict:
                    features_dict[index].append(i)
                else:
                    features_dict[index] = [i]
                in_polygon = True
                break
        if not in_polygon:
            features_without_poly[i] = [i]

    loas = list()
    index = 0
    for key in features_dict: 
        loa = create_loa_from_features(features, features_dict[key], index, True)
        loas.append(loa)
        index += 1
    for key in features_without_poly:
        loa = create_loa_from_features(features, features_without_poly[key], index, False)
        loas.append(loa)
        index += 1

    return loas