# Tileset Reader

The TilesetReader allows to read, merge and transform existing 3DTiles tilesets.

If you __only need to merge__ (without any translation, reprojection or scaling) the tilesets, use the [`tileset-merger`](#tileset-merger) command.

## Installation

See [installation notes](https://github.com/VCityTeam/py3dtilers/blob/master/README.md)

## TilesetReader features

### Run the TilesetReader

```bash
tileset-reader --paths <tileset_path>
```

Where `tileset_path` should point to the __root__ directory of a 3DTiles tileset.

If several paths to tilesets are putted after the `--paths` flag, all the tilesets will be red and merged into a single one.

```bash
tileset-reader --paths <path1> <path2> <path3> ...
```

All the triangles of the tiles will be loaded in memory to be able to transform them. If you don't want to transform the triangles, use the [`tileset-merger`](#tileset-merger) command instead.

The produced 3DTiles tileset will (by default) be in a directory named `tileset_reader_output`.

## Shared Tiler features

### Output directory

The flags `--output_dir`, `--out` or `-o` allow to choose the output directory of the Tiler.

```bash
tileset-reader --paths <tileset_path> --output_dir <output_directory_path>
```

### Obj creation

An .obj model (without texture) is created if the `--obj` flag is present in command line. To create an obj file, use:

```bash
tileset-reader --paths <tileset_path> --obj <obj_file_name>
```

### Scale

Rescale the features by a factor:

```bash
tileset-reader --paths <tileset_path> --scale 10
```

### Offset

Translate the features by __substracting__ an offset. :

```bash
tileset-reader --paths <tileset_path> --offset 10 20 30  # -10 on X, -20 on Y, -30 on Z
```

It is also possible to translate a tileset by its own centroid by using `centroid` as parameter:

```bash
tileset-reader --paths <tileset_path> --offset centroid
```

### CRS in/out

Project the features on another CRS. The `crs_in` flag allows to specify the input CRS (default is EPSG:3946). The `crs_out` flag projects the features in another CRS (default output CRS is EPSG:3946).

```bash
tileset-reader --paths <tileset_path> --crs_in EPSG:3946 --crs_out EPSG:4171
```

### With texture

Read the texture from the OBJ and write it in the produced 3DTiles:

```bash
tileset-reader --paths <tileset_path> --with_texture
```

### Geometric error

In 3DTiles, [the geometric error](https://github.com/CesiumGS/3d-tiles/tree/main/specification#geometric-error) is the metric used to refine a tile or not. A tile should always have a lower geometric error than its parent. The root of the tileset should have the highest geometric error and the leaves the lowest geometric error.

The geometric errors of the tiles can be overwrited with the flag `--geometric_error`. The values after the flag will be used (from left to right) for the deeper tiles (leaves), their parents (if existing), etc until the root tiles of the tileset.

```bash
tileset-reader --paths <tileset_path> --geometric_error 5 60 100  # Set leaf tiles GE to 5, their parents GE to 60 and root tiles GE to 100
```

You can set the geometric error of the basic tiles only with:

```bash
tileset-reader --paths <tileset_path> --geometric_error 5  # Set leaf tiles GE to 5
```

You can skip basic/LOD1 tiles geometric error by writing a non numeric character as geometric error.

```bash
tileset-reader --paths <tileset_path> --geometric_error x x 100  # Set root tiles GE to 100
```

## Tileset Merger

The TilesetMerger merges tilesets into a single one. All the texture images are copied.

The TilesetMerger can't translate, rescale or reproject the triangles.

### Run the TilesetMerger

```bash
tileset-merger --paths <tileset_path_1> <tileset_path_2> <tileset_path_3> ...
```

Where `tileset_path_x` should point to the __root__ directory of a 3DTiles tileset.

The produced 3DTiles tileset will be in a directory named `tileset_merger_output`.

Use `--output_dir`, `--out` or `-o` followed by the path of a directory to choose the output:

```bash
tileset-merger --paths <tileset_path_1> <tileset_path_2> --output_dir ../merged_tileset
```
