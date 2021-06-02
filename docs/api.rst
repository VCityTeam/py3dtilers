.. _api:
API usage
---------

Generic Tile
~~~~~~~~~~~~

The py3dtiles module provides some classes to fit into the
specification:

- *Tile* with a header *TileHeader* and a body *TileBody*
- *TileHeader* represents the metadata of the tile (magic value, version, ...)
- *TileBody* contains varying semantic and geometric data depending on the the tile's type

Moreover, a utility class *TileReader* is available to read a tile
file as well as a simple command line tool to retrieve basic information
about a tile: **py3dtiles\_info**. We also provide a utility to generate a
tileset from a list of 3D models in WKB format or stored in a postGIS table.


Point Cloud
~~~~~~~~~~~

Points Tile Format:
https://github.com/AnalyticalGraphicsInc/3d-tiles/tree/master/TileFormats/PointCloud

In the current implementation, the *Pnts* class only contains a *FeatureTable*
(*FeatureTableHeader* and a *FeatureTableBody*, which contains features of type
*Feature*).

**How to read a .pnts file**

.. code-block:: python

    >>> from py3dtiles import TileReader
    >>> from py3dtiles import Pnts
    >>>
    >>> filename = 'tests/pointCloudRGB.pnts'
    >>>
    >>> # read the file
    >>> tile = TileReader().read_file(filename)
    >>>
    >>> # tile is an instance of the Tile class
    >>> tile
    <py3dtiles.tile.Tile>
    >>>
    >>> # extract information about the tile header
    >>> th = tile.header
    >>> th
    <py3dtiles.tile.TileHeader>
    >>> th.magic_value
    'pnts'
    >>> th.tile_byte_length
    15176
    >>>
    >>> # extract the feature table
    >>> ft = tile.body.feature_table
    >>> ft
    <py3dtiles.feature_table.FeatureTable
    >>>
    >>> # display feature table header
    >>> ft.header.to_json()
    {'RTC_CENTER': [1215012.8828876738, -4736313.051199594, 4081605.22126042],
    'RGB': {'byteOffset': 12000}, 'POINTS_LENGTH': 1000, 'POSITION': {'byteOffset': 0}}
    >>>
    >>> # extract positions and colors of the first point
    >>> f = ft.feature(0)
    >>> f
    <py3dtiles.feature_table.Feature>
    >>> f.positions
    {'Y': 4.4896851, 'X': 2.19396, 'Z': -0.17107764}
    >>> f.colors
    {'Green': 243, 'Red': 44, 'Blue': 209}

**How to write a .pnts file**

To write a Point Cloud file, you have to build a numpy array with the
corresponding data type.

.. code-block:: python

    >>> from py3dtiles import Feature
    >>> import numpy as np
    >>>
    >>> # create the numpy dtype for positions with 32-bit floating point numbers
    >>> dt = np.dtype([('X', '<f4'), ('Y', '<f4'), ('Z', '<f4')])
    >>>
    >>> # create a position array
    >>> position = np.array([(4.489, 2.19, -0.17)], dtype=dt)
    >>>
    >>> # create a new feature from a uint8 numpy array
    >>> f = Feature.from_array(dt, position.view('uint8'))
    >>> f
    <py3dtiles.feature_table.Feature>
    >>> f.positions
    {'Y': 2.19, 'X': 4.489, 'Z': -0.17}
    >>>
    >>> # create a tile directly from our feature. None is for "no colors".
    >>> t  = Pnts.from_features(dt, None, [f])
    >>>
    >>> # the tile is complete
    >>> t.body.feature_table.header.to_json()
    {'POINTS_LENGTH': 1, 'POSITION': {'byteOffset': 0}}
    >>>
    >>> # to save our tile as a .pnts file
    >>> t.save_as("mypoints.pnts")


Batched 3D Model
~~~~~~~~~~~~~~~~

Batched 3D Model Tile Format:
https://github.com/AnalyticalGraphicsInc/3d-tiles/tree/master/TileFormats/Batched3DModel

**How to read a .b3dm file**

.. code-block:: python

    >>> from py3dtiles import TileReader
    >>> from py3dtiles import B3dm
    >>>
    >>> filename = 'tests/dragon_low.b3dm'
    >>>
    >>> # read the file
    >>> tile = TileReader().read_file(filename)
    >>>
    >>> # tile is an instance of the Tile class
    >>> tile
    <py3dtiles.tile.Tile>
    >>>
    >>> # extract information about the tile header
    >>> th = tile.header
    >>> th
    <py3dtiles.b3dm.B3dmHeader>
    >>> th.magic_value
    'b3dm'
    >>> th.tile_byte_length
    47246
    >>>
    >>> # extract the glTF
    >>> gltf = tile.body.glTF
    >>> gltf
    <py3dtiles.gltf.GlTF>
    >>>
    >>> # display gltf header's asset field
    >>> gltf.header['asset']
    {'premultipliedAlpha': True, 'profile': {'version': '1.0', 'api': 'WebGL'}, 'version': '1.0', 'generator': 'OBJ2GLTF'}

**How to write a .b3dm file**

To write a Batched 3D Model file, you have to import the geometry from a wkb
file containing polyhedralsurfaces or multipolygons.

.. code-block:: python

    >>> import numpy as np
    >>> from py3dtiles import GlTF, TriangleSoup
    >>>
    >>> # load a wkb file
    >>> wkb = open('tests/building.wkb', 'rb').read()
    >>>
    >>> # define the geometry's bouding box
    >>> box = [[-8.75, -7.36, -2.05], [8.80, 7.30, 2.05]]
    >>>
    >>> # define the geometry's world transformation
    >>> transform = np.array([
    ...             [1, 0, 0, 1842015.125],
    ...             [0, 1, 0, 5177109.25],
    ...             [0, 0, 1, 247.87364196777344],
    ...             [0, 0, 0, 1]], dtype=float)
    >>> transform = transform.flatten('F')
    >>>
    >>> # use the TriangleSoup helper class to transform the wkb into arrays
    >>> # of points and normals
    >>> ts = TriangleSoup.from_wkb_multipolygon(wkb)
    >>> positions = ts.getPositionArray()
    >>> normals = ts.getNormalArray()
    >>> # generate the glTF part from the binary arrays.
    >>> # notice that from_binary_arrays accepts array of geometries
    >>> # for batching purposes.
    >>> geometry = { 'position': positions, 'normal': normals, 'bbox': box }
    >>> gltf = GlTF.from_binary_arrays([geometry], transform)
    >>>
    >>> # create a b3dm tile directly from the glTF.
    >>> t = B3dm.from_glTF(glTF)
    >>>
    >>> # to save our tile as a .b3dm file
    >>> t.save_as("mymodel.b3dm")
