
# ObjTiler

## Running the ObjTiler

```bash
(venv) obj-tiler --paths <directory_path>
```

where `directory_path` should point to directories holding a set of OBJ files. 

The resulting 3DTiles tileset will contain all of the converted OBJ that are
located within this directory, using their filename as ID.

This command should produce a directory named `obj_tilesets`.

