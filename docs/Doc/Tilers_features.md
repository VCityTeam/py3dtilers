# Tilers features in py3dtilers

This document recaps the main features of the Tilers. For more detail about the usage/particularities of each tiler, see the [usage documentation](https://github.com/VCityTeam/py3dtilers#usage).

## Creation of 3DTiles

The Tilers allow to create 3DTiles tilesets from geospatial and urban data. They share common methods and a common structure.

![process](./UML/tiler_activity_smaller.drawio.png)

## Merge tilesets

To merge tilesets together, refer to the [TilesetReader notes](../../py3dtilers/TilesetReader/README.md).

The [TilesetReader](../../py3dtilers/TilesetReader/README.md#run-the-tilesetreader) also allows to transform the merged tilesets, but can have a heavy cost in time/memory.

```bash
tileset-reader --paths <path1> <path2>
```

The [TilesetMerger](../../py3dtilers/TilesetReader/README.md#run-the-tilesetmerger) can only merge the tilesets, but is faster and lighter than the `TilesetReader`.

```bash
tileset-merger --paths <path1> <path2>
```

Example of input tilesets:

```mermaid
graph TD;
    tileset_1[Tileset];
    tileset_2[Tileset];
    LOD1_tile_1[LOD1 Tile 1];
    LOD1_tile_2[LOD1 Tile 2];
    Detailled_tile_1[Detailled Tile 1];
    Detailled_tile_2[Detailled Tile 2];
    tileset_1-->LOD1_tile_1-->Detailled_tile_1;
    tileset_2-->LOD1_tile_2-->Detailled_tile_2;
```

Result after merge:

```mermaid
graph TD;
    LOD1_tile_1[LOD1 Tile 1];
    LOD1_tile_2[LOD1 Tile 2];
    Detailled_tile_1[Detailled Tile 1];
    Detailled_tile_2[Detailled Tile 2];
    Tileset-->LOD1_tile_1-->Detailled_tile_1;
    Tileset-->LOD1_tile_2-->Detailled_tile_2;
```

## Temporal 3DTiles

To create temporal 3DTiles, refer to the [CityTemporalTiler notes](../../py3dtilers/CityTiler/README.md#citytemporaltiler-features).

![city_tiler_temporal](https://user-images.githubusercontent.com/32875283/153201741-0538abfd-b352-4964-ac6d-6e7ac2ae6245.gif)

## Levels of detail

Description: Creates levels of detail in the tileset.

Flag(s): `--lod1` and `--loa <path>`

Example: `citygml-tiler --db_config_path config.yml --lod1 --loa polygons.geojson`

| Tiler | |
| --- | --- |
| CityTiler | :heavy_check_mark: |
| ObjTiler | :heavy_check_mark: |
| GeojsonTiler | :heavy_check_mark: |
| IfcTiler | :heavy_check_mark: |
| TilesetTiler | :x: |

![lod_gif](https://user-images.githubusercontent.com/32875283/153201793-620b84c5-5e30-466c-9d4a-f48e0566505a.gif)

## Texture

Description: Creates textured 3DTiles.

Flag(s): `--with_texture`

Example: `citygml-tiler --db_config_path config.yml --with_texture`

| Tiler | |
| --- | --- |
| CityTiler | :heavy_check_mark: |
| ObjTiler | :heavy_check_mark: |
| GeojsonTiler | :x: |
| IfcTiler | :x: |
| TilesetTiler | :heavy_check_mark: |

![image](https://user-images.githubusercontent.com/32875283/152002003-921dd838-8b51-4901-bcf0-d5819777bb9c.png)

## Color

Description: Creates colored 3DTiles.

Flag(s): `--add_color <attribute> <type>`

Example: `geojson-tiler --path buildings.geojson --add_color HEIGHT numeric`

| Tiler | |
| --- | --- |
| CityTiler | :heavy_check_mark: |
| ObjTiler | :x: |
| GeojsonTiler | :heavy_check_mark: |
| IfcTiler | :x: |
| TilesetTiler | :x: |

![image](https://user-images.githubusercontent.com/32875283/152183480-0b966fcc-eac2-4437-9fd0-fe3a9138d67b.png)

## Reprojection

Description: Projects the tileset in a different CRS.

Flag(s): `--crs_in <epsg>` and `--crs_out <epsg>`

Example: `citygml-tiler --db_config_path config.yml --crs_in EPSG:3946 --crs_out EPSG:4978`

| Tiler | |
| --- | --- |
| CityTiler | :heavy_check_mark: |
| ObjTiler | :heavy_check_mark: |
| GeojsonTiler | :heavy_check_mark: |
| IfcTiler | :heavy_check_mark: |
| TilesetTiler | :heavy_check_mark: |

![image](https://user-images.githubusercontent.com/32875283/153186832-4aefe413-4e97-46e9-9baf-4e037aa213f4.png)

## Scaling

Description: Rescale the 3DTiles.

Flag(s): `--scale <factor>`

Example: `obj-tiler --paths obj_models --scale 20`

| Tiler | |
| --- | --- |
| CityTiler | :heavy_check_mark: |
| ObjTiler | :heavy_check_mark: |
| GeojsonTiler | :heavy_check_mark: |
| IfcTiler | :heavy_check_mark: |
| TilesetTiler | :heavy_check_mark: |

![image](https://user-images.githubusercontent.com/32875283/153201146-f526c004-8e6e-4625-b21f-43e13b1aea07.png)

![image](https://user-images.githubusercontent.com/32875283/153201278-2345481f-0ebf-4c30-9234-02fca7d5b078.png)

## Translation

Description: Translates the tileset on \[x, y, z\] axis.

Flag(s): `--offset <x> <y> <z>`

Example: `geojson-tiler --path buildings.geojson --offset 0 0 100`

| Tiler | |
| --- | --- |
| CityTiler | :heavy_check_mark: |
| ObjTiler | :heavy_check_mark: |
| GeojsonTiler | :heavy_check_mark: |
| IfcTiler | :heavy_check_mark: |
| TilesetTiler | :heavy_check_mark: |

![image](https://user-images.githubusercontent.com/32875283/153202431-26eb17aa-3868-47f6-b4da-b14bdf337385.png)

![image](https://user-images.githubusercontent.com/32875283/153202841-caa485a6-4edf-4863-a029-6f403bacab0b.png)

## Export as OBJs

Description: Exports the leaves of the tileset as OBJ.

Flag(s): `--obj <file_name>`

Example: `citygml-tiler --db_config_path config.yml --obj buildings.obj`

| Tiler | |
| --- | --- |
| CityTiler | :heavy_check_mark: |
| ObjTiler | :heavy_check_mark: |
| GeojsonTiler | :heavy_check_mark: |
| IfcTiler | :heavy_check_mark: |
| TilesetTiler | :heavy_check_mark: |

![image](https://user-images.githubusercontent.com/32875283/153187343-dc93f529-8d2e-4961-ba3c-1ed25ed15b06.png)
