# Obj Tiler

## Installation

See [installation notes](https://github.com/VCityTeam/py3dtilers/blob/master/README.md)

## ObjTiler features

### Run the ObjTiler

To execute the ObjTiler, use the flag `-i` followed by paths of OBJ files or directories containing OBJ files

```bash
obj-tiler -i <path>
```

where `path` should point to an OBJ file or a directory holding a set of OBJ files.

The resulting 3DTiles tileset will contain all of the converted OBJ that are
located within the files, using their filename as ID.

This command should produce a directory named `obj_tilesets`.

## Shared Tiler features

See [Common module features](../Common/README.md#common-tiler-features).
