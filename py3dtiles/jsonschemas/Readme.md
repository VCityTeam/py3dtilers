Sources:
 * 3DTiles specifications **JSON** schemas:
   - [Core schemas](https://github.com/AnalyticalGraphicsInc/3d-tiles/tree/master/specification/schema)
   - Fix for jsonschema to work "properly":
     * boundingVolume.schema.json: oneOf entry replaced with anyOf (#FIXME)
        refer to https://github.com/tdegrunt/jsonschema/issues/180
        refer to https://stackoverflow.com/questions/24023536/how-do-i-require-one-field-or-another-or-one-of-two-others-but-not-all-of-them
 * Extensions:
      * [Batch Table Hierarchy](https://raw.githubusercontent.com/AnalyticalGraphicsInc/3d-tiles/master/extensions/3DTILES_batch_table_hierarchy/schema/3DTILES_batch_table_hierarchy.json). Warning: this schema had to be patched for [jsonschema to find the within-document references](https://github.com/Julian/jsonschema/issues/343)
