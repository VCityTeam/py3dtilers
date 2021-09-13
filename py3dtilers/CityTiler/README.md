# City Tiler

## Introduction
The CityTiler is a Python tiler which creates 3DTiles (.b3dm) from [3DCityDB](https://www.3dcitydb.org/3dcitydb/) databases.

The tiler can create 3DTiles of __buildings__, __terrains__ and __water bodies__.
## Installation
See https://github.com/VCityTeam/py3dtilers/blob/master/README.md

## Use the Tiler
### Run the CityTiler
Copy and customize the [CityTilerDBConfigReference.yml](CityTilerDBConfigReference.yml) file to provide database information.

You can then run the tiler by specifying the path to the _.yml_ configuration file:  
```
citygml-tiler <path_to_file>/Config.yml
```

The created tileset will be placed in a folder named `junk_<objects-type>` in the root directory. The name of the folder will be either `junk_buildings`, `junk_reliefs` or `junk_water_bodies`, depending on the [objects type](#objects-type) (respectively `building`, `relief` and `water`).
The output folder contains:

 * the resulting tileset file (with the .json extension)
 * a `tiles` folder containing the associated set of `.b3dm` files

### Objects type
By default, the tiler will treat the data as __buildings__. You can change the type by adding one the 3 keywords:

* `building`
```
citygml-tiler <path_to_file>/Config.yml building
```
* `relief`
```
citygml-tiler <path_to_file>/Config.yml relief
```
* `water`
```
citygml-tiler <path_to_file>/Config.yml water
```

### LOA
Using the LOA\* option creates a tileset with a __refinement hierarchy__. The leaves of the created tree are the detailed features (features loaded from the data source) and their parents are LOA geometries of those detailed features. The LOA geometries are 3D extrusions of polygons. The polygons must be given as a path to a directory containing geojson file(s) (the features in those geojsons must be Polygons or MultiPolygons). The polygons can for example be roads, boroughs, rivers or any other geographical partition.

To use the LOA option:
```
citygml-tiler <path_to_file>/Config.yml --loa <path-to-polygons>
```

\*_LOA (Level Of Abstraction): here, it is simple 3D extrusion of a polygon._

### LOD1
Using the LOD1 option creates a tileset with a __refinement hierarchy__. The leaves of the created tree are the detailed features (features loaded from the data source) and their parents are LOD1 geometries of those detailed features. The LOD1 geometries are 3D extrusions of the footprints of the features.

To use the LOD1 option:
```
citygml-tiler <path_to_file>/Config.yml --lod1
```

### Textures
By default, the objects are created without their texture.

To add texture:
```
citygml-tiler <path_to_file>/Config.yml --with_texture
```

### Split surfaces
By default, the tiler merges the surfaces of the same CityObject into one geometry. When using the `split_surfaces` flag, all surfaces will be an independent geometry.

To keep the surfaces split:
```
citygml-tiler <path_to_file>/Config.yml --split_surfaces
```
### Batch Table Hierarchy
The Batch table hierarchy is a [Batch Table](https://github.com/CesiumGS/3d-tiles/blob/main/specification/TileFormats/BatchTable/README.md) extension. This extension creates a link between the buildings and their surfaces.

To create the BatchTableHierarchy extension:
```
citygml-tiler <path_to_file>/Config.yml --with_BTH
```

# City Temporal Tiler
## Introduction
The City Temporal Tiler creates tilesets with a __temporal extension__. This extension allows to visualize the evolution of buildings through time.

## Use the Tiler
In order to run the CityTemporalTiler you will first need to obtain the so called [evolution difference files](https://github.com/VCityTeam/UD-Reproducibility/tree/master/Computations/3DTiles/LyonTemporal/PythonCallingDocker) between various temporal vintages. Let us assume such difference files were computed in between three time stamps (2009, 2012, 2015) and for two boroughs (`LYON_1ER` and `LYON_2EME`). Then the invocation of the `CityTemporalTiler` goes **from the home directory**:
```
citygml-tiler-temporal                                         \
  --db_config_path py3dtilers/CityTiler/CityTilerDBConfig2009.yml  \
                   py3dtilers/CityTiler/CityTilerDBConfig2012.yml  \
                   py3dtilers/CityTiler/CityTilerDBConfig2015.yml  \
  --time_stamps 2009 2012 2015                                  \
  --temporal_graph LYON_1ER_2009-2012/DifferencesAsGraph.json  \
                   LYON_1ER_2012-2015/DifferencesAsGraph.json  \
                   LYON_2EME_2009-2012/DifferencesAsGraph.json \
                   LYON_2EME_2012-2015/DifferencesAsGraph.json
```
