# Ifc Tiler

## Installation

See [installation notes](https://github.com/VCityTeam/py3dtilers/blob/master/README.md)

## See also

- [Understanding ifc geometry and processing](IFC_Geometry.md)

## IfcTiler features

### Run the IfcTiler

To execute the IfcTiler, use the flag `-i` followed by paths of IFC files or directories containing IFC files

```bash
(venv) ifc-tiler -i <path>
```

\<path\> should point to an IFC file or a directory holding IFC files.

The resulting 3DTiles tileset will contain the ifc geometry, ordered by category :
each tile will contain an IFC Object Type, that can be found in the batch table, along with its GUID

This command should produce a directory named "ifc_tileset".

### Group by

The `--grouped_by` flag allows to choose how to group the objects. The two are options are `IfcTypeObject` and `IfcGroup` (by default, the objects are grouped by type).

Group by `IfcTypeObject`:

```bash
ifc-tiler -i <path> --grouped_by IfcTypeObject
```

Group by `IfcGroup`:

```bash
ifc-tiler -i <path> --grouped_by IfcGroup
```

## Shared Tiler features

See [Common module features](../Common/README.md#common-tiler-features).
