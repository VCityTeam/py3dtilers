# Geojson Tiler

## Introduction

The GeojsonTiler is a Python tiler which creates 3DTiles (.b3dm) from [Geojsons](https://en.wikipedia.org/wiki/GeoJSON) files.
The tiler also creates .obj models.

Geojson files contain _features_. Each feature corresponds to a building and has a _geometry_ field. The geometry has _coordinates_. A feature is tied to a _properties_ containing data about the feature (for example height, precision, feature type...).

The Geojson files are computed with [QGIS](https://www.qgis.org/en/site/) from [IGN public data](https://geoservices.ign.fr/telechargement).

## Installation

See [installation notes](https://github.com/VCityTeam/py3dtilers/blob/master/README.md)

## GeojsonTiler features

### Run the GeojsonTiler

To execute the GeojsonTiler, use the flag `-i` followed by paths of Geojson files or directories containing Geojson files

Example:

```bash
geojson-tiler -i ../../geojsons/file.geojson
```

It will read ___file.geojson___ and parse it into 3DTiles.

```bash
geojson-tiler -i ../../geojsons/
```

It will read all .geojson and .json in the ___geojsons___ directory and parse them into 3DTiles.

```bash
geojson-tiler -i ../../file_1.geojson ../../geojsons
```

It will read ___file_1.geojson___ and all .geojson and .json in the ___geojsons___ directory, and parse them into 3DTiles.

### Roofprint or footprint

By default, the tiler considers that the polygons in the .geojson files are at the floor level. But sometimes, the coordinates can be at the roof level (especially for buildings). In this case, you can tell the tiler to consider the polygons as roofprints by adding the `--is_roof` flag. The tiler will substract the height of the feature from the coordinates to reach the floor level.

```bash
geojson-tiler -i <path> --is_roof
```

### Color

When present, the `--add_color` add a single colored material to each feature. The color of the material is determined by the value of a selected property for each feature.  
If the property is numeric, we create a [heatmap](https://en.wikipedia.org/wiki/Heat_map) by interpolating the [minimal](../Color/README.md#min_color) and the [maximal](../Color/README.md#max_color) colors.  
If the property is semantic, we choose the color depending on the value of the property. The color to use for each value __must__ be specified in the [color dictionary](../Color/README.md#color_dict).

The flag takes 2 arguments: the name of the property and its type ('numeric' or 'semantic'). If only the name is given, the type will be 'numeric' by default. If no argument is given with the flag, the colors won't be added.

Example for numeric property:

```bash
geojson-tiler -i <path> --add_color HEIGTH numeric
```

Example for semantic property:

```bash
geojson-tiler -i <path> --add_color NATURE semantic
```

The default colors are defined by a [JSON file](../Color/default_config.json). If you want to change the colors used, update the file with the right color codes. (__See [Color module](../Color/README.md) for more details__)

### Properties

The Tiler uses '_height_' property to create 3D tiles from features. The '_width_' property will be used __only when parsing LineString or MultiLineString__ features. This width will define the size of the buffer applied to the lines.  
The Tiler also uses the '_prec_' property to check if the altitude is usable and skip features without altitude (when the altitude is missing, the _prec_ is equal to 9999, so we skip features with prec >= 9999).  
A '_z_' property can be used to specify a Z value used for all the coordinates of the feature's geometry. By default, the Z will be the values in the coordinates.

By default, those properties are equal to:

- 'prec' --> 'PREC_ALTI'
- 'height' --> 'HAUTEUR'
- 'width' --> 'LARGEUR'
- 'z' --> use the Z from the coordinates

It means the tiler will target the property 'HAUTEUR' to find the height, 'LARGEUR' to find the width and 'PREC_ALTI' to find the altitude precision. The tiler won't override the Z values by default.

If the file doesn't contain those properties, you can change one or several property names to target in command line with `--height`, `--width` or `--prec`. If the features don't have a Z (2D features), a Z can be targeted with `--z`.

```bash
geojson-tiler -i <path> --height HEIGHT_NAME --width WIDTH_NAME --prec PREC_NAME --z Z_NAME
```

You can set the height, the width or the Z to a default value (used for all features). The value must be an _int_ or a _float_:

```bash
geojson-tiler -i <path> --height 10.5 --width 6.4 --z 100
```

If you want to skip the precision, you can set _prec_ to '_NONE_':

```bash
geojson-tiler -i <path> --prec NONE
```

### Keep properties

You can use the flag `-k` or `--keep_properties` to store the properties of the GeoJSON features in the batch table. All the properties of each feature will be stored.

```bash
geojson-tiler -i <path> --keep_properties
```

## Shared Tiler features

See [Common module features](../Common/README.md#common-tiler-features).
