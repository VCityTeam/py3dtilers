# Results of the mesh simplification

## Introduction
With the [GeoJsonTiler](https://github.com/LorenzoMarnat/py3dtiles/tree/Tiler/Tilers/GeojsonTiler), we create LOD1 models. Those models can be simplified to create LOD0 
models. By doing so, we reduce both the details and the number of polygons.

To do this simplification, we tried some methods:
* [Convex hull](https://en.wikipedia.org/wiki/Convex_hull)
* [Concave hull](https://gyaanipedia.fandom.com/wiki/Concave_hull)
* Group by cubes

## Results

### Convex hull
The [Python code](https://github.com/LorenzoMarnat/py3dtiles/blob/Tiler/Tilers/GeojsonTiler/geojson.py) uses the library [Scipy](https://docs.scipy.org/doc/scipy/reference/generated/scipy.spatial.ConvexHull.html)
to create convex hulls
