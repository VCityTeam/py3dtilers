# Geojson Tiler

## Introduction
The GeojsonTiler is a Python tiler which creates 3DTiles (.b3dm) from [Geojsons](https://en.wikipedia.org/wiki/GeoJSON) files.
The tiler also creates .obj models.

Geojson files contain _features_. Each feature corresponds to a building and has a _geometry_ field. The geometry has _coordinates_. A feature is tied to a _properties_ containing data about the feature (for example height, precision, feature type...).

The Geojson files are computed with [QGIS](https://www.qgis.org/en/site/) from public data.
## Installation
See https://github.com/Oslandia/py3dtiles/blob/master/docs/install.rst

## Use the Tiler
### Files path
To execute the GeojsonTiler, give the path of a folder containning .json or .geojson files

Example:
```
python Tilers/GeojsonTiler/GeojsonTiler.py --paths ../../geojson/
```
It will read all .geojson and .json it the _geojson_ directory and parse them into 3DTiles. It will also create a single .obj model from all readed files.

### Obj creation
The .obj model is created if the _--obj_ flag is present in command line. To create an obj file, use:
```
python Tilers/GeojsonTiler/GeojsonTiler.py --paths <path> --obj <obj_file_name>
```
If no name is specified after _--obj_, the .obj will be named "_result.obj_".

### Properties
The Tiler uses '_height_' and '_z_' properties to create 3D tiles from features. It also uses the '_prec_' property to check if the altitude is usable and skip features without altitude (when the altitude is missing, the _prec_ is equal to 9999, so we skip features with prec >= 9999).

By default, those properties are equal to:
- 'prec' --> 'PREC_ALTI'
- 'height' --> 'HAUTEUR'
- 'z' --> 'Z_MAX'

It means the tiler will target the property 'HAUTEUR' to find the height, 'Z_MAX' to find the z etc.

If the file don't have those properties, you can change one or several property names to target in command line with _--properties_:
```
python Tilers/GeojsonTiler/GeojsonTiler.py --paths <path> --properties height HEIGHT_NAME z Z_NAME prec PREC_NAME
```
If you want to skip the precision, you can set _prec_ to '_NONE_':
```
python Tilers/GeojsonTiler/GeojsonTiler.py --paths <path> --properties prec NONE
```

### Group method
You can also change the group method by using _--group_ in command line:
```
python Tilers/GeojsonTiler/GeojsonTiler.py --paths <path> --group <group_method> [<parameters>]*
```
Merging features together will reduce the __number of polygons__, but also the __level of detail__.  
By default, the group method is '_none_', meaning it won't merge features.
#### Cube
The 'cube' group method will merge features which are contained in the same cube of size '_size x size x size_'. The default size is _60_, but it can be changed in command line:
```
python Tilers/GeojsonTiler/GeojsonTiler.py --paths <path> --group cube 100
```
This line will call the tiler and group features into cubes with size _100 x 100 x 100_.

#### Road
The 'road' group method will create "_islets_" based on roads. The roads must be Geojson files containing _coordinates_ as _LineString_ and intersections between roads. The program will [create polygons](https://web.ist.utl.pt/alfredo.ferreira/publications/12EPCG-PolygonDetection.pdf) from a graph made with roads: each intersection of the roads is a vertex, each segment of road between two intersections is an edge.  
The group method can be used with _--group road_:
```
python Tilers/GeojsonTiler/GeojsonTiler.py --paths ../../geojson/ --group road
```
The roads will be load from the directory _roads_ in the <path>. This command will use _road group method_ with the roads file in ../../geojson/roads/
