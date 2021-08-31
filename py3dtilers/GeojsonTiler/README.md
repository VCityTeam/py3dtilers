# Geojson Tiler

## Introduction
The GeojsonTiler is a Python tiler which creates 3DTiles (.b3dm) from [Geojsons](https://en.wikipedia.org/wiki/GeoJSON) files.
The tiler also creates .obj models.

Geojson files contain _features_. Each feature corresponds to a building and has a _geometry_ field. The geometry has _coordinates_. A feature is tied to a _properties_ containing data about the feature (for example height, precision, feature type...).

The Geojson files are computed with [QGIS](https://www.qgis.org/en/site/) from [IGN public data](https://geoservices.ign.fr/telechargement).
## Installation
See https://github.com/VCityTeam/py3dtilers/blob/master/README.md

## Use the Tiler
### Files path
To execute the GeojsonTiler, use the flag `--path` followed by the path of a folder containing .json or .geojson files

Example:
```
geojson-tiler --path ../../geojson/
```
It will read all .geojson and .json in the _geojson_ directory and parse them into 3DTiles.

### LOA
Using the LOA\* option creates a tileset with a __refinement hierarchy__. The leaves of the created tree are the detailed features (features loaded from the data source) and their parents are LOA geometries of those detailed features. The LOA geometries are 3D extrusions of polygons. The polygons must be given as a path to a directory containing geojson file(s) (the features in those geojsons must be Polygons or MultiPolygons). The polygons can for example be roads, boroughs, rivers or any other geographical partition.

To use the LOA option:
```
geojson-tiler --path <path> --loa <path-to-polygons>
```

\*_LOA (Level Of Abstraction): here, it is simple 3D extrusion of a polygon._

### LOD1
___Warning__: creating LOD1 can be useless if the features are already footprints._


Using the LOD1 option creates a tileset with a __refinement hierarchy__. The leaves of the created tree are the detailed features (features loaded from the data source) and their parents are LOD1 geometries of those detailed features. The LOD1 geometries are 3D extrusions of the footprints of the features.

To use the LOD1 option:
```
geojson-tiler --path <path> --lod1
```
### Obj creation
The .obj model is created if the `--obj_` flag is present in command line. To create an obj file, use:
```
geojson-tiler --path <path> --obj <obj_file_name>
```

### Roofprint or footprint
By default, the tiler considers that the polygons in the .geojson files are at the floor level. But sometimes, the coordinates can be at the roof level (especially for buildings). In this case, you can tell the tiler to consider the polygons as roofprints by adding the `--is_roof` flag. The tiler will substract the height of the feature from the coordinates to reach the floor level.

```
geojson-tiler --path <path> --is_roof
```
### Properties
The Tiler uses '_height_' property to create 3D tiles from features. It also uses the '_prec_' property to check if the altitude is usable and skip features without altitude (when the altitude is missing, the _prec_ is equal to 9999, so we skip features with prec >= 9999).

By default, those properties are equal to:
- 'prec' --> 'PREC_ALTI'
- 'height' --> 'HAUTEUR'

It means the tiler will target the property 'HAUTEUR' to find the height and 'PREC_ALTI' to find the altitude precision.

If the file don't have those properties, you can change one or several property names to target in command line with `--height` or `--prec`:
```
geojson-tiler --path <path> --height HEIGHT_NAME --prec PREC_NAME
```
If you want to skip the precision, you can set _prec_ to '_NONE_':
```
geojson-tiler --path <path> --prec NONE
```
