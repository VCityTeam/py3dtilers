# City Tiler

## Introduction

The CityTiler is a Python tiler which creates 3DTiles (.b3dm) from [3DCityDB](https://www.3dcitydb.org/3dcitydb/) databases.

The tiler can create 3DTiles of __buildings__, __terrains__ and __water bodies__.

## Installation

See [installation notes](https://github.com/VCityTeam/py3dtilers/blob/master/README.md)

If you want to create your own local 3DCityDB databases, follow the [3DCityDB tutorial](https://github.com/VCityTeam/UD-SV/blob/master/ImplementationKnowHow/PostgreSQL_for_cityGML.md)

## CityTiler features

### Run the CityTiler

Copy and customize the [CityTilerDBConfigReference.yml](CityTilerDBConfigReference.yml) file to provide database information.

You can then run the tiler by specifying the path to the _.yml_ configuration file:

```bash
citygml-tiler -i <path_to_file>/Config.yml
```

The created tileset will be placed in a folder named `junk_<objects-type>` in the root directory. The name of the folder will be either `junk_buildings`, `junk_reliefs`, `junk_water_bodies` or `junk_bridges`, depending on the [objects type](#objects-type) (respectively `building`, `relief`, `water` and `bridge`).
The output folder contains:

* the resulting tileset file (with the .json extension)
* a `tiles` folder containing the associated set of `.b3dm` files
  * The database and GML IDs of objects in the tileset are stored in the [Batch Table](https://github.com/CesiumGS/3d-tiles/blob/main/specification/TileFormats/BatchTable/README.md) of each `.b3dm` file

If you run th Tiler from WSL (Windows Subsystem for Linux) and encounter the error

```bash
psycopg2.OperationalError: connection to server at "localhost" (127.0.0.1), port 5432 failed: Connection refused
        Is the server running on that host and accepting TCP/IP connections?
```

See [How to connect to Windows postgres database from WSL](https://stackoverflow.com/a/67596486), then find the WSL IP with

```bash
grep nameserver /etc/resolv.conf | awk '{print $2}'
```

Use this IP in your .yml config file.

### Objects type

By default, the tiler will treat the data as __buildings__. You can change the type by adding the flag `--type` followed by one the 4 keywords:

* `building`

```bash
citygml-tiler -i <path_to_file>/Config.yml --type building
```

* `relief`

```bash
citygml-tiler -i <path_to_file>/Config.yml --type relief
```

* `water`

```bash
citygml-tiler -i <path_to_file>/Config.yml --type water
```

* `bridge`

```bash
citygml-tiler -i <path_to_file>/Config.yml --type bridge
```

### Split surfaces

By default, the tiler merges the surfaces of the same CityObject into one `Feature` instance. When using the `split_surfaces` flag, all surfaces will be an independent `Feature` instance.

To keep the surfaces split:

```bash
citygml-tiler -i <path_to_file>/Config.yml --split_surfaces
```

### Batch Table Hierarchy

The Batch table hierarchy is a [Batch Table](https://github.com/CesiumGS/3d-tiles/blob/main/specification/TileFormats/BatchTable/README.md) extension. This extension creates a link between the buildings and their surfaces.

To create the BatchTableHierarchy extension:

```bash
citygml-tiler -i <path_to_file>/Config.yml --with_BTH
```

### Color

When present, the `--add_color` flag adds a single colored material to each feature. The color of the material is determined by CityGML `objectclass` of each feature.  

```bash
citygml-tiler -i <path_to_file>/Config.yml --add_color
```

If you want to apply different colors on the surfaces of buildings (roof, wall and floor), use the `--split_surfaces` flag:

```bash
citygml-tiler -i <path_to_file>/Config.yml --add_color --split_surfaces
```

The default colors are defined by a [JSON file](../Color/citytiler_config.json). If you want to change the colors used, update the file with the right color codes. (__See [Color module](../Color/README.md#color_dict) for more details__)

### ID filter

The flag `--keep_ids` and `--exclude_ids` allows to filter the CityObject(s). The flag must be followed by a list of __CityGML IDs__. See [ID filter](../Common/README.md#id-filter).

```bash
citygml-tiler -i <path_to_file>/Config.yml --keep_ids CityGML_ID_1 CityGML_ID_2
```

```bash
citygml-tiler -i <path_to_file>/Config.yml --exclude_ids CityGML_ID_1 CityGML_ID_2
```

## CityTemporalTiler features

The City Temporal Tiler creates tilesets with a [__temporal extension__](https://github.com/VCityTeam/UD-SV/tree/master/3DTilesTemporalExtention). This extension allows to visualize the evolution of buildings through time. For a detailed presentation of the input parameters and respective data formats, how that information gets transformed and represented within a resulting temporal 3DTiles, as well implementation notes [refer to this TemporalTiler design notes](../../docs/Doc/CityTemporalTilerDesignNotes.md).

### Run the CityTemporalTiler

In order to run the CityTemporalTiler you will first need to obtain the so called [difference files](https://github.com/VCityTeam/cityGMLto3DTiles/tree/master/PythonCallingDocker#running-the-temporal-tiler-workflow) between various temporal vintages. Let us assume such difference files were computed in between three time stamps (2009, 2012, 2015) and for two boroughs (`LYON_1ER` and `LYON_2EME`). Then the invocation of the `CityTemporalTiler` goes __from the home directory__:

```bash
citygml-tiler-temporal                                         \
  -i py3dtilers/CityTiler/CityTilerDBConfig2009.yml  \
                   py3dtilers/CityTiler/CityTilerDBConfig2012.yml  \
                   py3dtilers/CityTiler/CityTilerDBConfig2015.yml  \
  --time_stamps 2009 2012 2015                                  \
  --temporal_graph LYON_1ER_2009-2012/DifferencesAsGraph.json  \
                   LYON_1ER_2012-2015/DifferencesAsGraph.json  \
                   LYON_2EME_2009-2012/DifferencesAsGraph.json \
                   LYON_2EME_2012-2015/DifferencesAsGraph.json
```

## Shared Tiler features

See [Common module features](../Common/README.md#common-tiler-features).
