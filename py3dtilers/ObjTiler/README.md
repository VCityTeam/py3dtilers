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

See [Common module features](../Common/README.md#common-tiler-features).
