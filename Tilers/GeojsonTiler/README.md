# Geojson Tiler

## Introduction
The GeojsonTiler is a Python tiler which creates 3DTiles (.b3dm) from [Geojsons](https://en.wikipedia.org/wiki/GeoJSON) files.
The tiler also creates .obj models.

Geojson files contain _features_. Each feature corresponds to a building and has a _geometry_ field. The geometry has _coordinates_. A feature is tied to a _properties_ containing data about the feature (for example height, precision, feature type...).

## Installation
See https://github.com/Oslandia/py3dtiles/blob/master/docs/install.rst

## Use the Tiler
To execute the GeojsonTiler, give the path of a folder containning .json or .geojson files

Example:
```
python Tilers/GeojsonTiler/GeojsonTiler.py --paths ../../geojson/
```
It will read all .geojson and .json it the _geojson_ directory and parse them into 3DTiles. It will also create a single .obj model from all readed files.


The Tiler uses "HAUTEUR" (height) and "Z_MAX" properties to create 3D tiles from features. It also uses the "PREC_ALTI" (altitude precision) property to check if the altitude is usable and skip features without altitude (i.e sufficiently precise, when the altitude is missing, the PREC_ALTI is equal to 9999).
If the file don't have those properties, the tiler won't work and you'll have to modify the geojson.py
