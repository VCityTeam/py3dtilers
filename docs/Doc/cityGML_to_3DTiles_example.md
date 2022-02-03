# Example of CityGML to 3DTiles pipeline

This tutorial is an example of 3DTiles creation and visualisation. The 3DTiles are created with py3dtilers and viewed in [Cesium ion](https://cesium.com/ion).

In this example, we use the [CityGML Tiler](https://github.com/VCityTeam/py3dtilers/tree/master/py3dtilers/CityTiler) to create 3DTiles from a 3DCityDB database.

Before using the tiler, [install py3dtilers](https://github.com/VCityTeam/py3dtilers#installation-from-sources).

To create 3DTiles from OBJ, GeoJSON or IFC files, check the [Tilers usage](https://github.com/VCityTeam/py3dtilers#usage). An example of the GeojsonTiler is available in [this tutorial](geoJSON_to_3DTiles_example.md)

## Configure the database

Creating 3DTiles with the [CityGML Tiler](https://github.com/VCityTeam/py3dtilers/tree/master/py3dtilers/CityTiler) requires [Postgres/PostGIS](https://www.enterprisedb.com/downloads/postgres-postgresql-downloads) and [3DCityDB](https://www.3dcitydb.org/3dcitydb/downloads/). The cityGML data must be hosted in a 3DCityDB database to be used by the CityGML Tiler.  
To host CityGML in a local database, you can follow [__this tutorial__](https://github.com/VCityTeam/UD-SV/blob/master/ImplementationKnowHow/PostgreSQL_for_cityGML.md).

You also have to copy the content of the [configuration file](https://github.com/VCityTeam/py3dtilers/blob/master/py3dtilers/CityTiler/CityTilerDBConfigReference.yml) into another file (for example `py3dtilers/CityTiler/CityTilerDBConfig.yml`) and add the details of your database in this new file.

Download the cityGML data from [Data Grand Lyon](https://data.grandlyon.com/jeux-de-donnees/maquettes-3d-texturees-2018-communes-metropole-lyon/info) (you can choose which districts of Lyon you want to download). Then, import the buildings into a 3DCityDB database:

![import_buildings](https://github.com/VCityTeam/UD-Reproducibility/blob/master/Computations/3DTiles/Lyon_Relief_Roads_Buildings_Water/pictures/import_buildings.png)

## Use the CityTiler

To use the Tiler, target your database config file and choose the type `building` (see the [CityTiler usage](https://github.com/VCityTeam/py3dtilers/blob/master/py3dtilers/CityTiler/README.md) for more details):

```bash
citygml-tiler --db_config_path <path_to_file>/CityTilerDBConfig.yml --type building
```

### Levels of detail

To create [LOA](https://github.com/VCityTeam/py3dtilers/blob/master/py3dtilers/CityTiler/README.md#loa), you can for example use _BDTOPO/1_DONNEES_LIVRAISON/ADMINISTRATIF/__ARRONDISSEMENT.shp___ from BD Topo ([IGN](https://geoservices.ign.fr/telechargement)). To be able to use it, export the .shp as GeoJson with QGIS (__the projection must be the same as buildings__, i.e EPSG:3946 for Lyon's CityGML data).

To create the 3DTiles with levels of detail, run:

```bash
citygml-tiler --db_config_path <path_to_file>/CityTilerDBConfig.yml --lod1 --loa polygons.geojson
```

### Reprojection

The Tiler allows to change the CRS of the 3DTiles. By default, the CRS of your 3DTiles will be the same as your data.

In order to change the CRS, you have to specify both __input__ CRS (`--crs_in` flag) and __output__ CRS (`--crs_out` flag). For example, to visualise 3DTiles in Cesium ion (EPSG:4978) with Lyon's CityGML (EPSG:3946), you have to produce 3DTiles with:

```bash
citygml-tiler --db_config_path <path_to_file>/CityTilerDBConfig.yml --type building --crs_in EPSG:3946 --crs_out EPSG:4978
```

### Scale and translation

You can also rescale or translate your 3DTiles with the flags `--scale` and `--offset`. The `--offset` flag will translate the buildings by __substracting__ the offset to the position.

```bash
citygml-tiler --db_config_path <path_to_file>/CityTilerDBConfig.yml --type building --scale 1.5 --offset 1000 500 300
```

In the example above, the 3DTiles will be x1.5 bigger than the original data and have a translation of \[-1000, -500, -300\] (on \[x, y, z\] axis)

### Texture

By default, the 3DTiles are created without texture. To add the texture, just add the flag `--with_texture`:

```bash
citygml-tiler --db_config_path <path_to_file>/CityTilerDBConfig.yml --type building --with_texture
```

![image](https://user-images.githubusercontent.com/32875283/152002003-921dd838-8b51-4901-bcf0-d5819777bb9c.png)  
_Lyon's 1st borough buildings with texture_
