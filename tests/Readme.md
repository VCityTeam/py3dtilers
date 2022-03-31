# Tilers tests

## Notes concerning the data files

### Geojson

The [buildings footprints](geojson_tiler_test_data/buildings) were extracted from [IGN's BDTOPO](https://geoservices.ign.fr/ressource/159380) and transformed into GeoJson files with [QGIS](https://www.qgis.org/en/site/forusers/download.html).

The [polygons](geojson_tiler_test_data/polygons) were created from [IGN's roads](https://geoservices.ign.fr/ressource/159380) with QGIS.

### CityTiler

The .sql files were created with a `pg_dump` of 3DCityDB databases. To dump a database, see [this tutorial](https://github.com/VCityTeam/UD-SV/blob/master/ImplementationKnowHow/Dump_psql_postgis_database.md).

The [CityTiler's data](city_tiler_test_data/test_data.sql) contains small parts of a building, a water body and a terrain of CityGML files from [Grand Lyon's 3D models](https://data.grandlyon.com/jeux-de-donnees/maquettes-3d-texturees-2018-communes-metropole-lyon/info). The SQL file was created by doing a backup of a [3dcitydb database](https://www.3dcitydb.org/3dcitydb/).

The [CityTemporalTiler's data](city_temporal_tiler_test_data) contains small parts of buildings of CityGML files from [2009](https://data.grandlyon.com/jeux-de-donnees/maquettes-3d-texturees-2009-communes-metropole-lyon/info) and [2012](https://data.grandlyon.com/jeux-de-donnees/maquettes-3d-texturees-2012-communes-metropole-lyon/info) Grand Lyon's 3D models. The SQL files were created by doing a backup of [3dcitydb databases](https://www.3dcitydb.org/3dcitydb/).  
It also contains a [.json graph](city_temporal_tiler_test_data/graph_2009-2012.json) which links the 2009 building with the 2012 building. The graph was created with a [temporal tool](https://github.com/VCityTeam/cityGMLto3DTiles/tree/master/PythonCallingDocker).

### LOD tree

The [polygons](tiler_test_data/loa_polygons) were created from [IGN's roads](https://geoservices.ign.fr/ressource/159380) with QGIS.
