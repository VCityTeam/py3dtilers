## [object_to_tile](Common/object_to_tile.py)
### 🟠ObjectToTile
An [🟠](#objecttotile) _ObjectToTile_ instance contains a geometry and a bounding box.  
The geometry is a [TriangleSoup](https://github.com/VCityTeam/py3dtiles/blob/master/py3dtiles/wkb_utils.py), those triangles will be used to create the 3Dtiles geometry.
To set the triangles of an [🟠](#objecttotile) _ObjectToTile_, use:  
```
triangles = [[np.array([0., 0., 0.], dtype=np.float32), # First triangle
              np.array([1., 0., 0.], dtype=np.float32),
              np.array([1., 1., 0.], dtype=np.float32)],
             [np.array([0., 0., 1.], dtype=np.float32), # Second triangle
              np.array([1., 0., 1.], dtype=np.float32),
              np.array([1., 1., 1.], dtype=np.float32)]] # Each np.array is the coordinates of a vertice
object_to_tile = ObjectToTile("id")
object_to_tile.geom.triangles.append()
```
The bounding box is a box containing the [🟠](#objecttotile) _ObjectToTile_'s geometry. It can be set with:
```
object_to_tile.set_box()
```

### 🟣 ObjectsToTile
An [🟣](#objectstotile)&nbsp;_ObjectsToTile_ instance contains a collection of [🟠](#objecttotile)&nbsp;_ObjectToTile(s)_. To create an [🟣](#objectstotile)&nbsp;_ObjectsToTile_, use:
```
objects = [object_to_tile] # List of ObjectToTile(s)

objects_to_tile = ObjectsToTile(objects)
for object in objects_to_tile:
    print(object.get_id())
```

### 🟢 ObjectsToTileWithGeometry
An [🟢](#objectstotilewithgeometry)&nbsp;_ObjectsToTileWithGeometry_ contains objects to tile ([🟣](#objectstotile)&nbsp;_ObjectsToTile_) and can have its own geometry ([🟣](#objectstotile)&nbsp;_ObjectsToTile_).
It can be created with:
```
objects_to_tile_with_geom = ObjectsToTileWithGeometry(objects_to_tile, geometry) # Instance with its own geometry
# or
objects_to_tile_with_geom = ObjectsToTileWithGeometry(objects_to_tile) # Instance without its own geometry
```

## [kd_tree](Common/kd_tree.py)
The kd_tree distributes the [🟠](#objecttotile)&nbsp;_ObjectToTile(s)_ contained in an [🟣](#objectstotile)&nbsp;_ObjectsToTile_ into multiple [🟣](#objectstotile)&nbsp;_ObjectsToTile_. Each instance of [🟣](#objectstotile)&nbsp;_ObjectsToTile_ can have a maximum of `maxNumObjects`:
```
# Takes : an ObjectsToTile
# Returns : a list of ObjectsToTile
distributed_objects = kd_tree(objects_to_tile, 100) # Max 100 objects per ObjectsToTile
```

## [lod_tree](https://github.com/VCityTeam/py3dtilers/blob/CityTiler_with_LodTree/py3dtilers/Common/lod_tree.py)
lod_tree creates a tileset with a parent-child hierarchy. Each node of the tree contains an [🟣](#objectstotile)&nbsp;_ObjectsToTile_ (the geometries of the node) and a list of child nodes.
A node will correspond to a tile (.b3dm file) of the tileset.  
The leafs of the tree contain the geometries with the most details. The parent node of each node contains a lower level of details.

The lod_tree creation takes an [🟣](#objectstotile)&nbsp;_ObjectsToTile_ (containing [🟠](#objecttotile)&nbsp;_ObjectToTile(s)_ with detailled geometries and bounding boxes) and returns a tileset.

The first step of the tree creation is the distribution of [🟠](#objecttotile)&nbsp;_ObjectToTile(s)_ into groups. A group is an instance of [🟢](#objectstotilewithgeometry)&nbsp;_ObjectsToTileWithGeometry_ where the objects to tile ([🟣](#objectstotile)&nbsp;_ObjectsToTile_) are a group of detailled geometries. The group can also have its own geometry ([🟣](#objectstotile)&nbsp;_ObjectsToTile_), which is a lower level of details of the detailled geometries.
The groups are either created with `create_loa` or from the list of [🟣](#objectstotile)&nbsp;_ObjectsToTile_ of `kd_tree`. The groups from `create_loa` have their own geometry, those from `kd_tree` don't.

To create a tileset with LOA\*, use:
```
create_tileset(objects_to_tile, # Objects to transform into 3Dtiles
               also_create_loa=True, # Indicate to create a LOA
               loa_path="./path/to/dir") # Path to a directory if additional files are needed to create LOA
```
\* _Level Of Abstraction_, in this case it consists in a tile with a low level of details where the geometries are grouped into one.

Resulting tilesets:
Groups from `kd_tree` which __don't have__ their own geometry:

                            tileset
                              /\
                             /  \
                            /    \
                           /      \
                          /        \
               detailled tile     detailled tile
               
Groups from `create_loa` which __have__ their own geometry:

                            tileset
                              /\
                             /  \
                            /    \
                           /      \
                          /        \
                     loa tile     loa tile
                        /            \  
                       /              \
                      /                \
                     /                  \
                    /                    \
            detailled tile          detailled tile
            
LOD1 (Level Of Details 1) tiles can also be added in the tileset. A LOD1 is a simplified version of an [🟠](#objecttotile)&nbsp;_ObjectToTile_'s geometry.
It consists in a 3D extrusion of the footprint of the geometry.

To create a tileset with LOD1, use:
```
create_tileset(objects_to_tile, # Objects to transform into 3Dtiles
               also_create_lod1=True) # Indicate to create a LOD1
```
Resulting tilesets:

                            tileset
                              /\
                             /  \
                            /    \
                           /      \
                          /        \
                    lod1 tile     lod1 tile
                        /            \  
                       /              \
                      /                \
                     /                  \
                    /                    \
            detailled tile          detailled tile
            
A tileset can be created with both LOD1 and LOA with:
```
create_tileset(objects_to_tile, # Objects to transform into 3Dtiles
               also_create_lod1=True, # Indicate to create a LOD1
               also_create_loa=True, # Indicate to create a LOA
               loa_path="./path/to/dir") # Path to a directory if additional files are needed to create LOA
```
Resulting tilesets:

                            tileset
                              /\
                             /  \
                            /    \
                           /      \
                          /        \
                     loa tile     loa tile
                        /            \
                       /              \
                      /                \
                     /                  \
                    /                    \
               lod1 tile              lod1 tile
                  /                        \  
                 /                          \
                /                            \
               /                              \
              /                                \
        detailled tile                    detailled tile
