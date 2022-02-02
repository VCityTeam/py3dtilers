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

To execute the GeojsonTiler, use the flag `--path` followed by the path of a geojson file or a folder containing geojson files

Example:

```bash
geojson-tiler --path ../../geojsons/file.geojson
```

It will read ___file.geojson___ and parse it into 3DTiles.

```bash
geojson-tiler --path ../../geojsons/
```

It will read all .geojson and .json in the ___geojsons___ directory and parse them into 3DTiles.

### Roofprint or footprint

By default, the tiler considers that the polygons in the .geojson files are at the floor level. But sometimes, the coordinates can be at the roof level (especially for buildings). In this case, you can tell the tiler to consider the polygons as roofprints by adding the `--is_roof` flag. The tiler will substract the height of the feature from the coordinates to reach the floor level.

```bash
geojson-tiler --path <path> --is_roof
```

### Color

When present, the `--add_color` add a single colored material to each feature. The color of the material is determined by the value of a selected property for each feature.  
If the property is numeric, we create a [heatmap](https://en.wikipedia.org/wiki/Heat_map) by interpolating the [minimal](../Color/README.md#min_color) and the [maximal](../Color/README.md#max_color) colors.  
If the property is semantic, we choose the color depending on the value of the property. The color to use for each value __must__ be specified in the [color dictionary](../Color/README.md#color_dict).

The flag takes 2 arguments: the name of the property and its type ('numeric' or 'semantic'). If only the name is given, the type will be 'numeric' by default. If no argument is given with the flag, the colors won't be added.

Example for numeric property:

```bash
geojson-tiler --path <path> --add_color HEIGTH numeric
```

Example for semantic property:

```bash
geojson-tiler --path <path> --add_color NATURE semantic
```

The default colors are defined by a [JSON file](../Color/default_config.json). If you want to change the colors used, update the file with the right color codes. (__See [Color module](../Color/README.md) for more details__)

### Properties

The Tiler uses '_height_' property to create 3D tiles from features. The '_width_' property will be used __only when parsing LineString or MultiLineString__ geometries. This width will define the size of the buffer applied to the lines.  
The Tiler also uses the '_prec_' property to check if the altitude is usable and skip features without altitude (when the altitude is missing, the _prec_ is equal to 9999, so we skip features with prec >= 9999).  
A '_z_' property can be used to specify a Z value used for all the coordinates of the feature's geometry. By default, the Z will be the values in the coordinates.

By default, those properties are equal to:

- 'prec' --> 'PREC_ALTI'
- 'height' --> 'HAUTEUR'
- 'width' --> 'LARGEUR'
- 'z' --> use the Z from the coordinates

It means the tiler will target the property 'HAUTEUR' to find the height, 'LARGEUR' to find the width and 'PREC_ALTI' to find the altitude precision. The tiler won't override the Z values by default.

If the file doesn't contain those properties, you can change one or several property names to target in command line with `--height`, `--width` or `--prec`. If the geometries don't have a Z (2D geometries), a Z can be targeted with `--z`.

```bash
geojson-tiler --path <path> --height HEIGHT_NAME --width WIDTH_NAME --prec PREC_NAME --z Z_NAME
```

You can set the height, the width or the Z to a default value (used for all features). The value must be an _int_ or a _float_:

```bash
geojson-tiler --path <path> --height 10.5 --width 6.4 --z 100
```

If you want to skip the precision, you can set _prec_ to '_NONE_':

```bash
geojson-tiler --path <path> --prec NONE
```

## Shared Tiler features

### LOA

Using the LOA\* option creates a tileset with a __refinement hierarchy__. The leaves of the created tree are the detailed features (features loaded from the data source) and their parents are LOA geometries of those detailed features. The LOA geometries are 3D extrusions of polygons. The polygons must be given as a path to a Geojson file, or a directory containing Geojson file(s) (the features in those geojsons must be Polygons or MultiPolygons). The polygons can for example be roads, boroughs, rivers or any other geographical partition.

To use the LOA option:

```bash
geojson-tiler --path <path> --loa <path-to-polygons>
```

\*_LOA (Level Of Abstraction): here, it is simple 3D extrusion of a polygon._

### LOD1

___Warning__: creating LOD1 can be useless if the features are already footprints._

Using the LOD1 option creates a tileset with a __refinement hierarchy__. The leaves of the created tree are the detailed features (features loaded from the data source) and their parents are LOD1 geometries of those detailed features. The LOD1 geometries are 3D extrusions of the footprints of the features.

To use the LOD1 option:

```bash
geojson-tiler --path <path> --lod1
```

### Obj creation

An .obj model (without texture) is created if the `--obj` flag is present in command line. To create an obj file, use:

```bash
geojson-tiler --path <path> --obj <obj_file_name>
```

### Scale

Rescale the geometries by a factor:

```bash
geojson-tiler --path <path> --scale 10
```

### Offset

Translate the geometries by __substracting__ an offset. :

```bash
geojson-tiler --path <path> --offset 10 20 30  # -10 on X, -20 on Y, -30 on Z
```

It is also possible to translate a tileset by its own centroid by using `centroid` as parameter:

```bash
geojson-tiler --path <path> --offset centroid
```

### CRS in/out

Project the geometries on another CRS. The `crs_in` flag allows to specify the input CRS (default is EPSG:3946). The `crs_out` flag projects the geometries in another CRS (default output CRS is EPSG:3946).

```bash
geojson-tiler --path <path> --crs_in EPSG:3946 --crs_out EPSG:4171
```

### With texture
