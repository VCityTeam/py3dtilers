# Geojson Tiler

## Introduction
The GeojsonTiler is a Python tiler which creates 3DTiles (.b3dm) from [Geojsons](https://en.wikipedia.org/wiki/GeoJSON) files.
The tiler also creates .obj models.

## Installation
See https://github.com/Oslandia/py3dtiles/blob/master/docs/install.rst

## Use the Tiler
To execute the GeojsonTiler, give the path of a folder containning .json or .geojson files

Example:
```
python Tilers/GeojsonTiler/GeojsonTiler.py --paths ../../geojson
```

The Tiler uses "HAUTEUR" (height) and "Z_MAX" properties to create 3D tiles from features.
If the file don't have those properties, the tiler won't work and you'll have to modify the geojson.py
