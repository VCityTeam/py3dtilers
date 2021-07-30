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

### Group method
You can also change the group method by using `--group` in command line:
```
geojson-tiler --path <path> --group <group_method> [<parameters>]*
```
Merging features together will reduce the __number of polygons__, but also the __level of detail__.  
By default, the group method is '_none_', meaning it won't merge features.
#### Cube
The 'cube' group method will merge features which are contained in the same cube of size '_size x size x size_'. The default size is _60_, but it can be changed in command line:
```
geojson-tiler --path <path> --group cube 100
```
This line will call the tiler and group features into cubes with size _100 x 100 x 100_.

#### Road
The 'road' group method will create "_islets_" based on roads. The roads must be Geojson files containing _coordinates_ as _LineString_ and intersections between roads. The program will [create polygons](https://web.ist.utl.pt/alfredo.ferreira/publications/12EPCG-PolygonDetection.pdf) from a graph made with roads: each intersection of the roads is a vertex, each segment of road between two intersections is an edge.  
The group method can be used with `--group road`:
```
geojson-tiler --path <path> --group road
```
The roads will be loaded from the directory _roads_ in the \<path\>. This command will use _road group method_ with the roads file in \<path\>/roads/
  
#### Polygon
This solution follow the same process as the solution above, but in this case the polygons are __pre-computed__ with QGIS. In fact, the polygon detection described above takes a really long time when there is more than ~1000 vertices in the graph. Computing the polygons with QGIS before and loading them as a Geojson file at runtime is way faster.  
The group method can be used with `--group polygon`:
```
geojson-tiler --path <path> --group polygon
```
The roads will be loaded from the directory _polygons_ in the \<path\>. This command will use _polygon group method_ with the polygons file in \<path\>/polygons/
  
To polygonise the roads on QGIS, use the tool _Polygonize_ (_Processing --> Toolbox --> Vector Geometry --> Polygonize_)
