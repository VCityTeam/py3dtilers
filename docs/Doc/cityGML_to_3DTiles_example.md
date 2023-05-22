# Example of CityGML to 3DTiles pipeline

This tutorial is an example of 3DTiles creation and visualisation. The 3DTiles are created with py3dtilers.

In this example, we use the [CityGML Tiler](https://github.com/VCityTeam/py3dtilers/tree/master/py3dtilers/CityTiler) to create 3DTiles from a 3DCityDB database.

Before using the tiler, [install py3dtilers](https://github.com/VCityTeam/py3dtilers#installation-from-sources).

To create 3DTiles from OBJ, GeoJSON or IFC files, check the [Tilers usage](https://github.com/VCityTeam/py3dtilers#usage). An example of the GeojsonTiler usage is available in [this tutorial](geoJSON_to_3DTiles_example.md).

## Configure the database

Creating 3DTiles with the CityGML Tiler requires Postgres/PostGIS and 3DCityDB. The cityGML data must be hosted in a 3DCityDB database to be used by the CityGML Tiler.

Download the cityGML data from [Data Grand Lyon](https://data.grandlyon.com/jeux-de-donnees/maquettes-3d-texturees-2018-communes-metropole-lyon/info) (choose a district of Lyon, for example Lyon 1).

To host the downloaded CityGML in a local database, follow [__this tutorial__](https://github.com/VCityTeam/UD-SV/blob/master/ImplementationKnowHow/PostgreSQL_for_cityGML.md) to create a 3DCityDB database. Import the buildings into your database.

![import_buildings](https://github.com/VCityTeam/UD-Reproducibility/blob/master/Computations/3DTiles/Lyon_Relief_Roads_Buildings_Water/pictures/import_buildings.png).

You also have to copy the content of the [configuration file](https://github.com/VCityTeam/py3dtilers/blob/master/py3dtilers/CityTiler/CityTilerDBConfigReference.yml) into another file (for example `py3dtilers/CityTiler/CityTilerDBConfig.yml`) and add the details of your database in this new file:

```yml
PG_HOST: localhost
PG_PORT: 5432
PG_NAME: <name_of_your_database>
PG_USER: postgres
PG_PASSWORD: <user password>
```

## Use the CityTiler

_See the [CityTiler usage](https://github.com/VCityTeam/py3dtilers/blob/master/py3dtilers/CityTiler/README.md) for more details about this Tiler._

To use the Tiler, target your database config file and choose the type `building`:

```bash
citygml-tiler -i py3dtilers/CityTiler/CityTilerDBConfig.yml --type building
```

### Reprojection

The Tiler allows to change the CRS of the 3DTiles. By default, the CRS of your 3DTiles will be the same as your data.

In order to change the CRS, you have to specify both __input__ CRS (`--crs_in` flag) and __output__ CRS (`--crs_out` flag). For example, to visualise 3DTiles in Cesium ion (EPSG:4978) with Lyon's CityGML (EPSG:3946), you have to produce 3DTiles with:

```bash
citygml-tiler -i py3dtilers/CityTiler/CityTilerDBConfig.yml --type building --crs_in EPSG:3946 --crs_out EPSG:4978
```

### Texture

By default, the 3DTiles are created without texture. To add the texture, just add the flag `--with_texture`:

```bash
citygml-tiler -i py3dtilers/CityTiler/CityTilerDBConfig.yml --type building --with_texture
```

![image](https://user-images.githubusercontent.com/32875283/152002003-921dd838-8b51-4901-bcf0-d5819777bb9c.png)  
_Lyon's 1st borough buildings with texture_

## Visualisation

To visualize your 3DTiles in Cesium ion, iTowns or UD-Viz follow [__this tutorial__](https://github.com/VCityTeam/UD-SV/blob/master/ImplementationKnowHow/Visualize3DTiles.md).

### Cesium

Your 3DTiles must be in the __EPSG:4978__ to be viewed in Cesium ion (see [reprojection](#reprojection)).

The tileset is created with the command:

```bash
citygml-tiler -i py3dtilers/CityTiler/CityTilerDBConfig.yml --type building --crs_in EPSG:3946 --crs_out EPSG:4978
```

![image](https://user-images.githubusercontent.com/32875283/152802557-6eaa2b1a-ea8f-4ddc-bfb7-6c7545d708e6.png)

### iTowns

Your 3DTiles can be in any projection (e.g. __EPSG:3946__ or __EPSG:4978__) to be viewed in iTowns, as long as you declare the correct view and coordinate system (i.e. `Planar View` with any planar projection such as `EPSG:3946` or `Globe View` with `EPSG:4978`) (see [reprojection](#reprojection)). In this example, the 3D Tiles is in the `EPSG:3946` CRS (the CRS of the input CityGML file).

The tileset is created with the command:

```bash
citygml-tiler -i py3dtilers/CityTiler/CityTilerDBConfig.yml --type building
```

![image](https://user-images.githubusercontent.com/32875283/152807847-c92c1f41-7cc6-46eb-9478-b006ac9b54cd.png)

### UD-Viz

Similarly to iTowns, your 3DTiles can be in any projection (e.g. __EPSG:3946__ or __EPSG:4978__) to be viewed in UD-Viz, since it is based on iTowns. In this example, the 3D Tiles is in the `EPSG:3946` CRS (the CRS of the input CityGML file).

The tileset is created with the command:

```bash
citygml-tiler -i py3dtilers/CityTiler/CityTilerDBConfig.yml --type building
```

![image](https://user-images.githubusercontent.com/32875283/152802714-141f0697-3553-4467-b85f-60fb1b7f1312.png)
