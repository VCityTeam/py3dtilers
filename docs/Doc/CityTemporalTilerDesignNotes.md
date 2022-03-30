# CityTemporalTiler design notes

The CityTemporalTiler creates a 3DTiles tileset of buildings with a temporal extension.

More information about the temporal extension can be found in the [3DTiles Temporal Extenion documentation](https://github.com/VCityTeam/UD-SV/tree/master/3DTilesTemporalExtention).

To use the CityTemporalTiler, check the [CityTemporalTiler CLI documentation](../../py3dtilers/CityTiler#citytemporaltiler-features).

## Input of the tiler

The CityTemporalTiler creates a temporal 3DTiles from different vintages of buildings. Each vintage must be hosted in a [3DCityDB](https://www.3dcitydb.org/3dcitydb/) database (one database per vintage).

The tiler also needs a graph (as JSON file) where __each building__ of __each vintage__ is a node. The edges of the graph are __transactions__. A transaction is a modification between two vintages. Each transaction has a source, a target and a type of modification.

Example:

```json
{
    "nodes": [
        {
            "id": "0",  # ID of the node
            "globalid": "2009::LYON_1_00056_0"  # ID of the building
        },
        {
            "id": "1",  # ID of the node
            "globalid": "2012::LYON_1ER_00101_0"  # ID of the building
        }
    ],
    "edges": [
        {
            "id": "0",  # ID of the edge
            "source": "0",  # ID of the source node
            "target": "1",  # ID of the target node
            "type": "replace",  # type of modification
            "tags": "re-ided"
        }
    ]
}
```

### Create the graph from CityGML files

You can create the graph for __Lyon's boroughts__ by using [cityGMLto3DTiles](https://github.com/VCityTeam/cityGMLto3DTiles/tree/master/PythonCallingDocker#running-the-temporal-tiler-workflow).

## Resulting 3DTiles

The CityTemporalTiler creates a 3DTiles with the temporal extension. The extension adds information in the JSON file of the tileset and in the batch table of each tile.

### Tileset

In the tileset.json, the transactions are written with:

- an `id`: the ID of the transaction
- a `startDate`: the vintage of the source
- a `endDate`: the vintage of the destination
- a `source`: the ID(s) of the builing(s) of the starting state
- a `destination`: the ID(s) of the building(s) of the ending state

Example of tileset.json:

```json
{
  "asset": {...},
  "geometricError": 500.0,
  "root": {...},
  "extensions": {
    "3DTILES_temporal": {
      "startDate": 2009,
      "endDate": 2015,
      "transactions": [
        {
          "id": "0",
          "startDate": 2009,
          "endDate": 2012,
          "tags": [],
          "source": ["2009::LYON_1_00005_15"],
          "destination": ["2012::LYON_1ER_00152_15"],
          "type": "modification"
        },
        {
          "id": "1",
          "startDate": 2009,
          "endDate": 2012,
          "tags": [],
          "source": ["2009::LYON_1_00026_0"],
          "destination": ["2012::LYON_1ER_00131_0"],
          "type": "modification"
        }
      ]
    }
  }
}
```

### Tile

Each tile have addtional information written as JSON in its batch table. The extension is named `3DTiles_temporal` and associates attributes to the batched models (with [batchIds](https://github.com/CesiumGS/3d-tiles/blob/main/specification/TileFormats/Batched3DModel/README.md#batch-table). Those attributes are:

- startDates: the year when the building should be added to the view
- endDates: the year when the building should be removed from the view
- featureIds: the ID of the building
