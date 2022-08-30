# Tileset Reader

The TilesetReader allows to read, merge and transform existing 3DTiles tilesets.

If you __only need to merge__ (without any translation, reprojection or scaling) the tilesets, use the [`tileset-merger`](#tileset-merger) command.

## Installation

See [installation notes](https://github.com/VCityTeam/py3dtilers/blob/master/README.md)

## TilesetReader features

### Run the TilesetReader

```bash
tileset-reader -i <tileset_path>
```

Where `tileset_path` should point to the __root__ directory of a 3DTiles tileset.

If several paths to tilesets are put after the `-i` flag, all the tilesets will be red and merged into a single one.

```bash
tileset-reader -i <path1> <path2> <path3> ...
```

All the triangles of the tiles will be loaded in memory to be able to transform them. If you don't want to transform the triangles, use the [`tileset-merger`](#tileset-merger) command instead.

The produced 3DTiles tileset will (by default) be in a directory named `tileset_reader_output`.

## Shared Tiler features

See [Common module features](../Common/README.md#common-tiler-features).

## Tileset Merger

The TilesetMerger merges tilesets into a single one. All the texture images are copied.

The TilesetMerger can't translate, rescale or reproject the triangles.

### Run the TilesetMerger

```bash
tileset-merger -i <tileset_path_1> <tileset_path_2> <tileset_path_3> ...
```

Where `tileset_path_x` should point to the __root__ directory of a 3DTiles tileset.

The produced 3DTiles tileset will be in a directory named `tileset_merger_output`.

Use `--output_dir`, `--out` or `-o` followed by the path of a directory to choose the output:

```bash
tileset-merger -i <tileset_path_1> <tileset_path_2> --output_dir ../merged_tileset
```
