# Obj Tiler

## Installation

See [installation notes](https://github.com/VCityTeam/py3dtilers/blob/master/README.md)

## ObjTiler features

### Run the ObjTiler

```bash
(venv) obj-tiler --paths <directory_path>
```

where `directory_path` should point to directories holding a set of OBJ files.

The resulting 3DTiles tileset will contain all of the converted OBJ that are
located within this directory, using their filename as ID.

This command should produce a directory named `obj_tilesets`.

## Shared Tiler features

### Output directory

The flags `--output_dir`, `--out` or `-o` allow to choose the output directory of the Tiler.

```bash
obj-tiler --paths <directory_path> --output_dir <output_directory_path>
```

### LOA

Using the LOA\* option creates a tileset with a __refinement hierarchy__. The leaves of the created tree are the detailed features (features loaded from the data source) and their parents are LOA features of those detailed features. The LOA features are 3D extrusions of polygons. The polygons must be given as a path to a Geojson file, or a directory containing Geojson file(s) (the features in those geojsons must be Polygons or MultiPolygons). The polygons can for example be roads, boroughs, rivers or any other geographical partition.

To use the LOA option:

```bash
obj-tiler --paths <directory_path> --loa <path-to-polygons>
```

\*_LOA (Level Of Abstraction): here, it is simple 3D extrusion of a polygon._

### LOD1

___Warning__: creating LOD1 can be useless if the features are already footprints._

Using the LOD1 option creates a tileset with a __refinement hierarchy__. The leaves of the created tree are the detailed features (features loaded from the data source) and their parents are LOD1 features of those detailed features. The LOD1 features are 3D extrusions of the footprints of the features.

To use the LOD1 option:

```bash
obj-tiler --paths <directory_path> --lod1
```

### Obj creation

An .obj model (without texture) is created if the `--obj` flag is present in command line. To create an obj file, use:

```bash
obj-tiler --paths <directory_path> --obj <obj_file_name>
```

### Scale

Rescale the features by a factor:

```bash
obj-tiler --paths <directory_path> --scale 10
```

### Offset

Translate the features by __substracting__ an offset. :

```bash
obj-tiler --paths <directory_path> --offset 10 20 30  # -10 on X, -20 on Y, -30 on Z
```

It is also possible to translate a tileset by its own centroid by using `centroid` as parameter:

```bash
obj-tiler --paths <directory_path> --offset centroid
```

### CRS in/out

Project the features on another CRS. The `crs_in` flag allows to specify the input CRS (default is EPSG:3946). The `crs_out` flag projects the features in another CRS (default output CRS is EPSG:3946).

```bash
obj-tiler --paths <directory_path> --crs_in EPSG:3946 --crs_out EPSG:4171
```

### With texture

Read the texture from the OBJ and write it in the produced 3DTiles:

```bash
obj-tiler --paths <directory_path> --with_texture
```
