# -*- coding: utf-8 -*-
from .schema_with_sample import SchemaWithSample


class TemporalBatchTableSchemaWithSample(SchemaWithSample):

    def __init__(self):
        super().__init__('TemporalBatchTable')
        self.set_directory('py3dtiles/jsonschemas')
        self.set_filename('3DTILES_temporal.batchTable.schema.json')
        self.set_sample(
            {
                "startDates": ["2018-01-01"],
                "endDates":   ["2019-01-01"],
                "featureIds": ["some feature"]
            }
        )


class TemporalBoundingVolumeSchemaWithSample(SchemaWithSample):

    def __init__(self):
        super().__init__('TemporalBoundingVolume')
        self.set_directory('py3dtiles/jsonschemas')
        self.set_filename('3DTILES_temporal.boundingVolume.schema.json')
        self.set_sample(
            {
                "startDate": "2018-01-01",
                "endDate":   "2019-01-01"
            }
        )


class TemporalTileSetSchemaWithSample(SchemaWithSample):

    def __init__(self):
        super().__init__('TemporalTileSet')
        self.set_directory('py3dtiles/jsonschemas')
        self.set_filename('3DTILES_temporal.tileset.schema.json')
        self.set_sample(
            {
                "startDate": "2018-01-01",
                "endDate":   "2019-01-01",
                "versions": [
                    {
                        "id": 0,
                        "startDate": "2018-01-01",
                        "endDate": "2019-01-01",
                        "type": "insert",
                        "tags": ["heightened"],
                        "source": ["some-id"],
                        "destination": ["some-id"],
                    }
                ]
            }
        )

class TemporalTransactionSchemaWithSample(SchemaWithSample):

    def __init__(self):
        super().__init__('TemporalTransaction')
        self.set_directory('py3dtiles/jsonschemas')
        self.set_filename('3DTILES_temporal.transaction.schema.json')
        self.set_sample(
            {
                "id": "0",
                "startDate": "2018-01-01",
                "endDate": "2019-01-01",
                "tags": ["heightened"],
                "source": ["some-id", "some-other-id"],
                "destination": ["a given id", "another given id"],
            }
        )


class TemporalPrimaryTransactionSchemaWithSample(SchemaWithSample):

    def __init__(self):
        super().__init__('TemporalPrimaryTransaction')
        self.set_directory('py3dtiles/jsonschemas')
        self.set_filename('3DTILES_temporal.primaryTransaction.schema.json')
        self.set_sample(
            {
                "id": "0",
                "startDate": "2018-01-01",
                "endDate": "2019-01-01",
                "type": "creation",
                "tags": ["heightened"],
                "source": ["some-id", "some-other-id"],
                "destination": ["a given id", "another given id"],
            }
        )


class TemporalTransactionAggregateSchemaWithSample(SchemaWithSample):

    def __init__(self):
        super().__init__('TemporalTransactionAggregate')
        self.set_directory('py3dtiles/jsonschemas')
        self.set_filename('3DTILES_temporal.transactionAggregate.schema.json')
        self.set_sample(
            {
                "id": "0",
                "startDate": "2018-01-01",
                "endDate": "2019-01-01",
                "tags": ["heightened"],
                "source": ["some-id", "some-other-id"],
                "destination": ["a given id", "another given id"],
                "transactions": [
                    {
                        "id": "0",
                        "startDate": "2018-01-01",
                        "endDate": "2019-01-01",
                        "type": "creation",
                        "tags": ["heightened"],
                        "source": ["some-id", "some-other-id"],
                        "destination": ["a given id", "another given id"]
                    }
                ],
            }
        )


class TemporalVersionSchemaWithSample(SchemaWithSample):

    def __init__(self):
        super().__init__('TemporalVersion')
        self.set_directory('py3dtiles/jsonschemas')
        self.set_filename('3DTILES_temporal.version.schema.json')
        self.set_sample(
            {
                "id": 0,
                "startDate": "2018-01-01",
                "endDate": "2019-01-01",
                "name": "some version name",
                "versionMembers": ["version 1", "version 2", "version 3"],
                "tags": ["some tag version", "some other tag version"]
            }
        )


class TemporalVersionTransitionSchemaWithSample(SchemaWithSample):

    def __init__(self):
        super().__init__('TemporalVersionTransition')
        self.set_directory('py3dtiles/jsonschemas')
        self.set_filename('3DTILES_temporal.versionTransition.schema.json')
        self.set_sample(
            {
                "name": "Version Transition Name",
                "startDate": "2018-01-01",
                "endDate": "2019-01-01",
                "from": 100,
                "to":   200,
                "reason": "Reason of evolution between two versions",
                "type": "merge",
                "transactions": [1000, 2000]
            }
        )


class TemporalExtensionSchemas(list):
    def __init__(self, *args):
        list.__init__(self, *args)
        self.append(TemporalBatchTableSchemaWithSample())
        self.append(TemporalBoundingVolumeSchemaWithSample())
        self.append(TemporalTileSetSchemaWithSample())
        self.append(TemporalTransactionSchemaWithSample())
        self.append(TemporalPrimaryTransactionSchemaWithSample())
        self.append(TemporalTransactionAggregateSchemaWithSample())
        self.append(TemporalVersionSchemaWithSample())
        self.append(TemporalVersionTransitionSchemaWithSample())
