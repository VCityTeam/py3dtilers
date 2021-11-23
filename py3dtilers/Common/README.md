## [object_to_tile](object_to_tile.py)
### ObjectToTile
An [:large_blue_circle:](#objecttotile)&nbsp;_ObjectToTile_ instance contains a geometry, a bounding box, and optionally can contain semantic data.  
The geometry is a [TriangleSoup](https://github.com/VCityTeam/py3dtiles/blob/master/py3dtiles/wkb_utils.py), those triangles will be used to create the 3Dtiles geometry.
To set the triangles of an [:large_blue_circle:](#objecttotile)&nbsp;_ObjectToTile_, use:  
```
triangles = [[np.array([0., 0., 0.], dtype=np.float32), # First triangle
              np.array([1., 0., 0.], dtype=np.float32),
              np.array([1., 1., 0.], dtype=np.float32)],
             [np.array([0., 0., 1.], dtype=np.float32), # Second triangle
              np.array([1., 0., 1.], dtype=np.float32),
              np.array([1., 1., 1.], dtype=np.float32)]] # Each np.array is a vertex with [x, y, z] coordinates
object_to_tile = ObjectToTile("id")
object_to_tile.geom.triangles.append()
```
The bounding box is a box containing the [:large_blue_circle:](#objecttotile)&nbsp;_ObjectToTile_'s geometry. It can be set with:
```
object_to_tile.set_box()
```

The semantic data contained in the object represents application specific data. This data can be added to the [Batch Table](https://github.com/CesiumGS/3d-tiles/blob/main/specification/TileFormats/BatchTable/README.md) in 3Dtiles.

This data must be structured as a [Dictionary](https://www.w3schools.com/python/python_dictionaries.asp) of key/value pairs and can be set with:
```
object_to_tile.set_batchtable_data()
```

### ObjectsToTile
An [:red_circle:](#objectstotile)&nbsp;_ObjectsToTile_ instance contains a collection of [:large_blue_circle:](#objecttotile)&nbsp;_ObjectToTile(s)_. To create an [:red_circle:](#objectstotile)&nbsp;_ObjectsToTile_, use:
```
objects = [object_to_tile] # List of ObjectToTile(s)

objects_to_tile = ObjectsToTile(objects)
for object in objects_to_tile:
    print(object.get_id())
```

## [obj_writer](obj_writer.py)
This class allows to write [:red_circle:](#objectstotile)&nbsp;_ObjectsToTile_ in as an OBJ model. To write geometries in a file, use:

```
obj_writer = ObjWriter()
obj_writer.add_geometries(geometries)   # geometries contains ObjectToTile instances
obj_writer.write_obj(file_name)
```

## [polygon_extrusion](polygon_extrusion.py)
An instance of _ExtrudedPolygon_ contains a footprint (a polygon as list of points, and a point is a list of float), a minimal height and a maximal height.

The static method `create_footprint_extrusion` from _ExtrudedPolygon_ allows to create an [:large_blue_circle:](#objecttotile)&nbsp;_ObjectToTile_ which is the extrusion of the footprint of another [:large_blue_circle:](#objecttotile)&nbsp;_ObjectToTile_. The height of the extrusion will be _max height - min height_ of the _ExtrudedPolygon_

To create an extrusion, use:
```
extruded_object = ExtrudedPolygon.create_footprint_extrusion(object_to_tile)
```
_Note_: the footprint to extrude is computed from the `object_to_tile` param, but you can give another polygon to extrude (that will replace the footprint):
```
extruded_object = ExtrudedPolygon.create_footprint_extrusion(object_to_tile, override_points=True, polygon=points)
```
## [group](group.py)
An instance of _Group_ contains objects to tile ([:red_circle:](#objectstotile)&nbsp;_ObjectsToTile_). It can also contains additional data which is polygons (a polygon as list of points, and a point is a list of float) and a dictionary to stock the indexes of the geometries contained in each polygon.

The static methods in the _Group_ class allow to distribute [:red_circle:](#objectstotile)&nbsp;_ObjectsToTile_ into groups following specific rules.  
The groups can be created with:
```
# Group together the objects which are in the same polygon
# Takes : an ObjectsToTile, a path to a Geojson file containing polygons, or a folder containing Geojson files
groups = Group.group_objects_by_polygons(objects_to_tile, polygons_path)
```
```
# Group together the objects with close centroids
# Takes : an ObjectsToTile
groups = Group.group_objects_with_kdtree(objects_to_tile)
```

## [kd_tree](kd_tree.py)
The kd_tree distributes the [:large_blue_circle:](#objecttotile)&nbsp;_ObjectToTile(s)_ contained in an [:red_circle:](#objectstotile)&nbsp;_ObjectsToTile_ into multiple [:red_circle:](#objectstotile)&nbsp;_ObjectsToTile_. Each instance of [:red_circle:](#objectstotile)&nbsp;_ObjectsToTile_ can have a maximum of `maxNumObjects`:
```
# Takes : an ObjectsToTile
# Returns : a list of ObjectsToTile
distributed_objects = kd_tree(objects_to_tile, 100) # Max 100 objects per ObjectsToTile
```

## [lod_node](lod_node.py)
### LodNode
A _LodNode_ contains geometries as [:red_circle:](#objectstotile)&nbsp;_ObjectsToTile_ and a list of child nodes. It also contains a [geometric error](http://docs.opengeospatial.org/cs/18-053r2/18-053r2.html#27) which is the distance to display the 3D tile created from this node.

To create a _LodNode_:
```
# Takes : geometries as ObjectsToTile, a geometric error (int)
# Returns : a node containing the geometries
node = LodNode(objects_to_tile, geometric_error=20)
```
To add a child to a node:
```
node.add_child_node(other_node)
```
### Lod1Node
_Lod1Node_ inherits from _LodNode_. When instanced, a _Lod1Node_ creates a 3D extrusion of the footprint of each [:large_blue_circle:](#objecttotile)&nbsp;_ObjectToTile_ in the [:red_circle:](#objectstotile)&nbsp;_ObjectsToTile_ parameter.

To create a _Lod1Node_:
```
# Takes : geometries as ObjectsToTile, a geometric error (int)
# Returns : a node containing 3D extrusions of the geometries
node = Lod1Node(objects_to_tile, geometric_error=20)
```

### LoaNode
_LoaNode_ inherits from _LodNode_. When instanced, a _LoaNode_ creates a 3D extrusion of the polygons (list of points, where a point is a list of float) given as parameter. The _LoaNode_ also takes a dictionary stocking the indexes of the [:large_blue_circle:](#objecttotile)&nbsp;_ObjectToTile(s)_ contained in each polygon.

To create a _LoaNode_:
```
# Takes : geometries as ObjectsToTile,
          a geometric error (int),
          a list of polygons,
          a dictionary {polygon_index -> [object_index(es)]}
# Returns : a node containing 3D extrusions of the polygons
node = LoaNode(objects_to_tile, geometric_error=20, additional_points=polygons, points_dict=dictionary)
```

## [lod_tree](lod_tree.py)
lod_tree creates a tileset with a parent-child hierarchy. Each node of the tree contains an [:red_circle:](#objectstotile)&nbsp;_ObjectsToTile_ (the geometries of the node) and a list of child nodes.
A node will correspond to a tile (.b3dm file) of the tileset.  
The leaves of the tree contain the geometries with the most details. The parent node of each node contains a lower level of details.

The lod_tree creation takes an [:red_circle:](#objectstotile)&nbsp;_ObjectsToTile_ (containing [:large_blue_circle:](#objecttotile)&nbsp;_ObjectToTile(s)_ with detailled geometries and bounding boxes) and returns a tileset.

The first step of the tree creation is the distribution of [:large_blue_circle:](#objecttotile)&nbsp;_ObjectToTile(s)_ into groups. A group is an instance of [_Group_](#group) where the objects to tile ([:red_circle:](#objectstotile)&nbsp;_ObjectsToTile_) are a group of detailed geometries. The group can also contains additional data which is polygons and a dictionary to stock the indexes of the geometries contained in each polygon, this additional data is used to create [_LoaNode(s)_](#loanode).  
The groups are either created with polygons or with the kd_tree (see [group](#group)).

To create a tileset with LOA\*, use:
```
create_tileset(objects_to_tile, # Objects to transform into 3Dtiles
               also_create_loa=True, # Indicate to create a LOA
               polygons_path="./path/to/dir") # Path to a Geojson file containing polygons, or a folder with many Geojson files
```
\* _Level Of Abstraction_, it consists in a tile with a low level of details and an abstract geometry representing multiple geometries (for example a cube to represent a block of buildings).

Resulting tilesets:

If no level of details is added:

                            tileset
                              /\
                             /  \
                            /    \
                           /      \
                          /        \
               detailled tile     detailled tile
               
If the LOA is created:

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
            
LOD1 (Level Of Details 1) tiles can also be added in the tileset. A LOD1 is a simplified version of an [:large_blue_circle:](#objecttotile)&nbsp;_ObjectToTile_'s geometry.
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
               polygons_path="./path/to/dir") # Path to a Geojson file containing polygons, or a folder with many Geojson files
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
