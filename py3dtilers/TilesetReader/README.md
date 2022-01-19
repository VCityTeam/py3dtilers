# Tileset Reader

## Installation

See [installation notes](https://github.com/VCityTeam/py3dtilers/blob/master/README.md)

## TilesetReader features

### Run the TilesetReader

```bash
tileset-reader --path <tileset_path>
```

Where `tileset_path` should point to the __root__ directory of a 3DTiles tileset.

The produced 3DTiles will be in a directory named `tileset_reader_output`.

### Merge tilesets

The `--merge` flag allows to merge other tilesets with the main tileset (the one after the `--path` flag). To do so, add the paths of the __root__ of the additional tilesets after the `--merge` flag:

```bash
tileset-reader --path <tileset_path> --merge <path2> <path3> ...
```

## Shared Tiler features

### Obj creation

An .obj model (without texture) is created if the `--obj` flag is present in command line. To create an obj file, use:

```bash
tileset-reader --paths <tileset_path> --obj <obj_file_name>
```

### Scale

Rescale the geometries by a factor:

```bash
tileset-reader --paths <tileset_path> --scale 10
```

### Offset

Translate the geometries by __substracting__ an offset. :

```bash
tileset-reader --paths <tileset_path> --offset 10 20 30  # -10 on X, -20 on Y, -30 on Z
```

It is also possible to translate a tileset by its own centroid by using `centroid` as parameter:

```bash
tileset-reader --paths <tileset_path> --offset centroid
```

### CRS in/out

Project the geometries on another CRS. The `crs_in` flag allows to specify the input CRS (default is EPSG:3946). The `crs_out` flag projects the geometries in another CRS (default output CRS is EPSG:3946).

```bash
tileset-reader --paths <tileset_path> --crs_in EPSG:3946 --crs_out EPSG:4171
```

### With texture

Read the texture from the OBJ and write it in the produced 3DTiles:

```bash
tileset-reader --paths <tileset_path> --with_texture
```
