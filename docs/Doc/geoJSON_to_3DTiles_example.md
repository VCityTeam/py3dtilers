# Example of GeoJSON to 3DTiles pipeline

This tutorial is an example of 3DTiles creation and visualisation. The 3DTiles are created with py3dtilers.

In this example, we use the [GeoJSON Tiler](https://github.com/VCityTeam/py3dtilers/tree/master/py3dtilers/GeojsonTiler) to create 3DTiles from a GeoJSON file.

Before using the tiler, [install py3dtilers](https://github.com/VCityTeam/py3dtilers#installation-from-sources).

To create 3DTiles from OBJ, CityGML or IFC files, check the [Tilers usage](https://github.com/VCityTeam/py3dtilers#usage). An example of the CityGML Tiler usage is available in [this tutorial](cityGML_to_3DTiles_example.md)

## Data

Download the BD Topo data from IGN's [BD Topo](https://geoservices.ign.fr/telechargement) (ZONE --> `D069 Rhône`)

In [QGIS](https://www.qgis.org/en/site/), open the _BDTOPO/1_DONNEES_LIVRAISON/BATI/__BATIMENT.shp___ file.

You can use QGIS to filter buildings or select a smaller area.

Then, save the buildings layer as a GeoJson file:

![image](https://user-images.githubusercontent.com/32875283/152004767-954ead5e-5cff-4c74-bca5-820c9702805e.png)

## Use the GeojsonTiler

_See the [GeoJson Tiler usage](https://github.com/VCityTeam/py3dtilers/blob/master/py3dtilers/GeojsonTiler/README.md) for more details about this Tiler._

To use the Tiler, target the GeoJSON file containing the buildings:

```bash
geojson-tiler --path path/to/buildings.geojson
```

### Reprojection

The Tiler allows to change the CRS of the 3DTiles. By default, the CRS of your 3DTiles will be the same as your data.

In order to change the CRS, you have to specify both __input__ CRS (`--crs_in` flag) and __output__ CRS (`--crs_out` flag). For example, to visualise 3DTiles in Cesium ion (EPSG:4978) with IGN's BD Topo (EPSG:2154), you have to produce 3DTiles with:

```bash
geojson-tiler --path path/to/buildings.geojson --crs_in EPSG:2154 --crs_out EPSG:4978
```

### Roofprint or footprint

By default, the Tiler considers that the features in the GeoJSON file are __footprints__. But in BD TOPO data, the features are __roofprints__, meaning we have to substract the height of the building from the features to find the footprints.

If the features are roofprints, use the flag `--is_roof` to create the buildings at the right altitude:

```bash
geojson-tiler --path path/to/buildings.geojson --is_roof
```

### Altitude and height

You can choose an arbitrary altitude and an arbitrary height for your buildings with the flags `--z` and `--height`. For example, to create 6 meters hight buildings at 0 m above the sea level, use:

```bash
geojson-tiler --path path/to/buildings.geojson --height 6 --z 0
```

### Color

You can add colors to your buildings with the flag `--add_color`. The color of the material depends on the value of a selected property for each building.  
If the property is numeric, we create a [heatmap](https://en.wikipedia.org/wiki/Heat_map) by interpolating the [minimal](../../py3dtilers/Color/README.md#min_color) and the [maximal](../../py3dtilers/Color/README.md#max_color) colors.  
If the property is semantic, we choose the color depending on the value of the property. The color to use for each value __must__ be specified in the [color dictionary](../../py3dtilers/Color/README.md#color_dict).

The flag takes 2 arguments: the name of the property and its type ('numeric' or 'semantic'). If only the name is given, the type will be 'numeric' by default. If no argument is given with the flag, the colors won't be added.

Example for numeric property:

```bash
geojson-tiler --path path/to/buildings.geojson --add_color HAUTEUR numeric
```

![image](https://user-images.githubusercontent.com/32875283/152183480-0b966fcc-eac2-4437-9fd0-fe3a9138d67b.png)  
_The color depends on the "HAUTEUR" ("height") of each building. The highter is the building, more the color tends to red_

Example for a semantic property __arbitrarily added__ with QGIS:

```bash
geojson-tiler --path path/to/buildings.geojson --add_color BOROUGH semantic
```

![image](https://user-images.githubusercontent.com/32875283/152183142-2bb18d7d-d8f2-4377-94cc-6f926a841a9b.png)  
_The color depends on the "BOROUGH" attribute of each building ("2nd" -> red, "3rd" -> green, "7th" -> blue)_

The default colors are defined by a [JSON file](../../py3dtilers/Color/default_config.json). If you want to change the colors used, update the file with the right color codes. (__See [Color module](../../py3dtilers/Color/README.md) for more details__)

## Visualisation

To visualize your 3DTiles in Cesium ion, iTowns or UD-Viz follow [__this tutorial__](https://github.com/VCityTeam/UD-SV/blob/master/ImplementationKnowHow/Visualize3DTiles.md).

### Cesium ion

Your 3DTiles must be in the __EPSG:4978__ to be viewed in Cesium ion (see [reprojection](#reprojection)).

The tileset is created with the command:

```bash
geojson-tiler --path ../buildings.geojson --z 0 --crs_in EPSG:2154 --crs_out EPSG:4978
```

![image](https://user-images.githubusercontent.com/32875283/152801507-a0bdcd2c-2040-4e2a-8a46-470353593255.png)

### iTowns

Your 3DTiles must be in the __EPSG:3946__ to be viewed in iTowns (see [reprojection](#reprojection)).

The tileset is created with the command:

```bash
geojson-tiler --path ../buildings.geojson --is_roof --crs_in EPSG:2154 --crs_out EPSG:3946
```

![image](https://user-images.githubusercontent.com/32875283/152789884-b2c1a0a8-de9b-4b3b-9db0-d396e36b7a72.png)

### UD-Viz

Your 3DTiles must be in the __EPSG:3946__ to be viewed in UD-Viz (see [reprojection](#reprojection)).

The tileset is created with the command:

```bash
geojson-tiler --path ../buildings.geojson --is_roof --crs_in EPSG:2154 --crs_out EPSG:3946
```

![image](https://user-images.githubusercontent.com/32875283/152801893-afc9e0e3-ebe7-488b-b3f5-1cab5cce994d.png)
