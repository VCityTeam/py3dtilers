# Example of GeoJSON to 3DTiles pipeline

This tutorial is an example of 3DTiles creation and visualisation. The 3DTiles are created with py3dtilers and viewed in [Cesium ion](https://cesium.com/ion).

In this example, we use the [GeoJSON Tiler](https://github.com/VCityTeam/py3dtilers/tree/master/py3dtilers/GeojsonTiler) to create 3DTiles from a GeoJSON file.

Before using the tiler, [install py3dtilers](https://github.com/VCityTeam/py3dtilers#installation-from-sources).

To create 3DTiles from OBJ, CityGML or IFC files, check the [Tilers usage](https://github.com/VCityTeam/py3dtilers#usage). An example of the CityGML Tiler is available in [this tutorial](cityGML_to_3DTiles_example.md)

## Data

Download the BD Topo data from [IGN](https://geoservices.ign.fr/telechargement)

In [QGIS](https://www.qgis.org/en/site/), open the _BDTOPO/1_DONNEES_LIVRAISON/BATI/__BATIMENT.shp___ file.

You can use QGIS to filter buildings or select a smaller area.

Then, save the buildings layer as a GeoJson file:

![image](https://user-images.githubusercontent.com/32875283/152004767-954ead5e-5cff-4c74-bca5-820c9702805e.png)

## Use the GeojsonTiler

To use the Tiler, target your database config file and choose the type `building` (see the [CityTiler usage](https://github.com/VCityTeam/py3dtilers/blob/master/py3dtilers/CityTiler/README.md) for more details):

```bash
geojson-tiler --path path/to/buildings.geojson
```

### Levels of detail

To create [LOA](https://github.com/VCityTeam/py3dtilers/blob/master/py3dtilers/GeojsonTiler/README.md#loa), you can for example use _BDTOPO/1_DONNEES_LIVRAISON/ADMINISTRATIF/__ARRONDISSEMENT.shp___ from BD Topo ([IGN](https://geoservices.ign.fr/telechargement)). To be able to use it, export the .shp as GeoJson with QGIS (__the projection must be the same as buildings__).

To create the 3DTiles with levels of detail, run:

```bash
geojson-tiler --path path/to/buildings.geojson --lod1 --loa polygons.geojson
```

### Reprojection

The Tiler allows to change the CRS of the 3DTiles. By default, the CRS of your 3DTiles will be the same as your data.

In order to change the CRS, you have to specify both __input__ CRS (`--crs_in` flag) and __output__ CRS (`--crs_out` flag). For example, to visualise 3DTiles in Cesium ion (EPSG:4978) with IGN's BD Topo (EPSG:2154), you have to produce 3DTiles with:

```bash
geojson-tiler --path path/to/buildings.geojson --crs_in EPSG:2154 --crs_out EPSG:4978
```

_Warning_: reprojection don't work for LODs. If you want to change the CRS, don't create LODs in your 3DTiles.

### Scale and translation

You can also rescale or translate your 3DTiles with the flags `--scale` and `--offset`. The `--offset` flag will translate the buildings by __substracting__ the offset to the position.

```bash
geojson-tiler --path path/to/buildings.geojson --scale 1.5 --offset 1000 500 300
```

In the example above, the 3DTiles will be x1.5 bigger than the original data and have a translation of \[-1000, -500, -300\] (on \[x, y, z\] axis)

### Color

You can add colors to your buildings with the flag `--add_color`. The color of the material depends on the value of a selected property for each building.  
If the property is numeric, we create a [heatmap](https://en.wikipedia.org/wiki/Heat_map) by interpolating the [minimal](../py3dtilers/Color/README.md#min_color) and the [maximal](../py3dtilers/Color/README.md#max_color) colors.  
If the property is semantic, we choose the color depending on the value of the property. The color to use for each value __must__ be specified in the [color dictionary](../py3dtilers/Color/README.md#color_dict).

The flag takes 2 arguments: the name of the property and its type ('numeric' or 'semantic'). If only the name is given, the type will be 'numeric' by default. If no argument is given with the flag, the colors won't be added.

Example for numeric property:

```bash
geojson-tiler --path <path> --add_color HEIGHT numeric
```

![image](https://user-images.githubusercontent.com/32875283/152183480-0b966fcc-eac2-4437-9fd0-fe3a9138d67b.png)  
_The color depends on the "HEIGHT" of each building. The highter is the building, more the color tends to red_

Example for semantic property:

```bash
geojson-tiler --path <path> --add_color BOROUGH semantic
```

![image](https://user-images.githubusercontent.com/32875283/152183142-2bb18d7d-d8f2-4377-94cc-6f926a841a9b.png)  
_The color depends on the "BOROUGH" attribute of each building ("2nd" -> red, "3rd" -> green, "7th" -> blue)_

The default colors are defined by a [JSON file](../py3dtilers/Color/default_config.json). If you want to change the colors used, update the file with the right color codes. (__See [Color module](../py3dtilers/Color/README.md) for more details__)
