# Results of the mesh simplification

## Introduction
With the [GeoJsonTiler](https://github.com/LorenzoMarnat/py3dtiles/tree/Tiler/Tilers/GeojsonTiler), we create LOD1 models. Those models can be simplified to create LOD0 
models. By doing so, we reduce both the details and the number of polygons.

The models are made with [public GeoJson files](https://geoservices.ign.fr/documentation/diffusion/telechargement-donnees-libres.html#bd-topo) of Lyon.

To do this simplification, we tried some methods:
* [Convex hull](https://en.wikipedia.org/wiki/Convex_hull)
* [Concave hull](https://gyaanipedia.fandom.com/wiki/Concave_hull)
* Group by cubes

## Results
### Base model
The [base model](https://github.com/LorenzoMarnat/py3dtiles/blob/Tiler/Tilers/GeojsonTiler/Results/Obj_models/partDieu_baseModel.obj) is a LOD1 model of Part-Dieu (Lyon, France). The model has more than 100 000 faces and 50 000 vertices.
![baseModel](https://github.com/LorenzoMarnat/py3dtiles/blob/Tiler/Tilers/GeojsonTiler/Results/ScreenShots/baseModel.png)
![baseModel_tris](https://github.com/LorenzoMarnat/py3dtiles/blob/Tiler/Tilers/GeojsonTiler/Results/ScreenShots/baseModel_tris.png)
### Convex hull
The [Python code](https://github.com/LorenzoMarnat/py3dtiles/blob/Tiler/Tilers/GeojsonTiler/geojson.py) uses the library [Scipy](https://docs.scipy.org/doc/scipy/reference/generated/scipy.spatial.ConvexHull.html)
to create convex hulls.
```
from scipy.spatial import ConvexHull

hull = ConvexHull(coords)
coords = [coords[i] for i in reversed(hull.vertices)]
```
![convexHull](https://github.com/LorenzoMarnat/py3dtiles/blob/Tiler/Tilers/GeojsonTiler/Results/ScreenShots/convexHull.png)
![convexHull_tris](https://github.com/LorenzoMarnat/py3dtiles/blob/Tiler/Tilers/GeojsonTiler/Results/ScreenShots/convexHull_tris.png)
### Concave hull

### Group by cube
The _group by cube_ method create a 3D grid. Each cube of this grid has an arbitrary size (see [Group method -> Cube](https://github.com/LorenzoMarnat/py3dtiles/blob/Tiler/Tilers/GeojsonTiler/README.md)). All features of the Geojsons will be distributed in the cubes according to their center (mean of all their coordinates). To do so, we create a dictionary with the cubes with at least one feature and the indexes of the features they contain:
```
# Create a dictionary key: cubes center (x,y,z); value: list of features index
for i in range(0,len(features)):
    closest_cube = Geojsons.round_coordinate(features[i].center,size)
    if tuple(closest_cube) in features_dict:
        features_dict[tuple(closest_cube)].append(i)
    else:
        features_dict[tuple(closest_cube)] = [i]
``` 

Once the features are distributed, we merge the features in the same cube to create one feature by cube. We also apply a convex hull on those new features to keep only usefull coordinates.
#### Size of 50
![cube50](https://github.com/LorenzoMarnat/py3dtiles/blob/Tiler/Tilers/GeojsonTiler/Results/ScreenShots/cube50.png)
![cube50_tris](https://github.com/LorenzoMarnat/py3dtiles/blob/Tiler/Tilers/GeojsonTiler/Results/ScreenShots/cube50_tris.png)
#### Size of 75
![cube75](https://github.com/LorenzoMarnat/py3dtiles/blob/Tiler/Tilers/GeojsonTiler/Results/ScreenShots/cube75.png)
![cube75_tris](https://github.com/LorenzoMarnat/py3dtiles/blob/Tiler/Tilers/GeojsonTiler/Results/ScreenShots/cube75_tris.png)
