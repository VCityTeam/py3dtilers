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

### Models as LODs

`--as_lods` allows to create a tileset from several OBJ files, where the first file is the least detailled model and the last file the most detailled. It will create a refinement hierarchy from the least detailled model to the most detailled model.

In this example, `model_0.obj` is the least detailled model:

```bash
obj-tiler -i model_0.obj model_1.obj model_2.obj --as_lods --geometric_error 1 4 8
```

If OBJ files are in the correct order in the folder:

```bash
obj-tiler -i <path>\objs\ --as_lods --geometric_error 1 4 8
```

## Shared Tiler features

See [Common module features](../Common/README.md#common-tiler-features).
