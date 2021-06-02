# -*- coding: utf-8 -*-
from .schema_with_sample import SchemaWithSample


class BatchTableSchemaWithSample(SchemaWithSample):

    def __init__(self):
        super().__init__('BatchTable')
        self.set_directory('py3dtiles/jsonschemas')
        self.set_filename('batchTable.schema.json')
        self.set_sample(
            {
                "ids": [1, 2]
            }
        )


class BoundingVolumeBoxSchemaWithSample(SchemaWithSample):

    def __init__(self):
        super().__init__('BoundingVolumeBox')
        self.set_directory('py3dtiles/jsonschemas')
        self.set_filename('boundingVolume.schema.json')
        self.set_sample(
          {
              "box": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
          }
        )


class BoundingVolumeRegionSchemaWithSample(SchemaWithSample):

    def __init__(self):
        super().__init__('BoundingVolumeRegion')
        self.set_directory('py3dtiles/jsonschemas')
        self.set_filename('boundingVolume.schema.json')
        # Defining a sample would be useless since it would not be checked:
        # refer to the code of SchemaValidators::register_schema_with_sample()
        # for the technical reasons, that boil down to the fact that
        # BoundingVolumeRegion and BoundingVolumeBox share the same
        # json schema (file). In sake for clarification (of this limitation)
        # we thus here avoid to misleadingly make you believe that such a
        # sample would be used
        #      bounding_volume_region.set_sample()


class BoundingVolumeSphereSchemaWithSample(SchemaWithSample):

    def __init__(self):
        super().__init__('BoundingVolumeSphere')
        self.set_directory('py3dtiles/jsonschemas')
        self.set_filename('boundingVolume.schema.json')
        # Concerning the non setting of a sample refer to the corresponding
        # comment in BoundingVolumeRegionSchemaWithSample
        #      bounding_volume_region.set_sample()


class TileSchemaWithSample(SchemaWithSample):

    def __init__(self):
        super().__init__('Tile')
        self.set_directory('py3dtiles/jsonschemas')
        self.set_filename('tile.schema.json')
        self.set_sample(
            {
                "geometricError": 3.14159,
                "boundingVolume": {
                    "box": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
                }
            }
        )


class TileSetSchemaWithSample(SchemaWithSample):

    def __init__(self):
        super().__init__('TileSet')
        self.set_directory('py3dtiles/jsonschemas')
        self.set_filename('tileset.schema.json')
        self.set_sample(
            {
                "asset": {"version": "1.0"},
                "geometricError": 3.14159,
                "root": {
                    "boundingVolume": {
                        "box": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
                    },
                    "geometricError": 3.14159
                }
            }
        )


class ThreeDTilesCoreSchemas(list):
    def __init__(self, *args):
        list.__init__(self, *args)
        self.append(BatchTableSchemaWithSample())
        self.append(BoundingVolumeBoxSchemaWithSample())
        self.append(BoundingVolumeRegionSchemaWithSample())
        self.append(BoundingVolumeSphereSchemaWithSample())
        self.append(TileSchemaWithSample())
        self.append(TileSetSchemaWithSample())
