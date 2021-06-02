Command line usage
------------------

info
~~~~

Here is an example on how to retrieve basic information about a tile, in this
case *pointCloudRGB.pnts*:

.. code-block:: shell

    $ py3dtiles info tests/pointCloudRGB.pnts
    Tile Header
    -----------
    Magic Value:  pnts
    Version:  1
    Tile byte length:  15176
    Feature table json byte length:  148
    Feature table bin byte length:  15000

    Feature Table Header
    --------------------
    {'POSITION': {'byteOffset': 0}, 'RGB': {'byteOffset': 12000}, 'POINTS_LENGTH': 1000, 'RTC_CENTER': [1215012.8828876738, -4736313.051199594, 4081605.22126042]}

    First point
    -----------
    {'Z': -0.17107764, 'Red': 44, 'X': 2.19396, 'Y': 4.4896851, 'Green': 243, 'Blue': 209}


convert
~~~~~~~

The convert sub-command can be used to convert one or several .las file to a 3dtiles tileset.

It also support crs reprojection of the points (see py3dtiles convert --help for all the options).


.. code-block:: shell

    py3dtiles convert mypointcloud.las --out /tmp/destination


merge
~~~~~

The merge feature is a special use case: it generates a meta-tileset from a group of existing tilesets.

It's useful to be able only a part of a pointcloud. For instance: if one has 6 input las file (A.las, B.las, ..., F.las), there are 2 solutions to vizualize them all in a 3dtiles viewer:
  * run `py3dtiles convert A.las B.las ... F.las` and diplay the resulting tileset
  * or run `py3dtiles convert A.las`, then `py3dtiles convert B.las`, ... and then run `py3dtiles merge`

  The advantage of the 2nd option, is that it allows to update a part of the pointcloud easily.
  e.g: if a new B.las is available, with option 1 the full tileset has to be rebuild from scratch, while with option 2, only the B.las part has to be rebuilt + the merge command.


export
~~~~~~

Two export modes are available, the database export or the directory export.
They both transform all the geometries provided in .b3dm files, along with a
tileset.json file which organizes them.

The directory export will use all the .wkb files in the provided directory.
Warning: the coordinates are read as floats, not doubles. Make sure to offset
the coordinates beforehand to reduce their size. Afterwards, you can indicate
in the command line the offset that needs to be applied to the tileset so it is
correctly placed. Usage example:

.. code-block:: shell

    $ export_tileset -d my_directory -o 10000 10000 0

The database export requires a user name, a database name, the name of the table
and its column that contains the geometry and (optionaly) the name of the column
that contains the object's ID. Usage example:

.. code-block:: shell

    $ export_tileset -D database -t my_city -c geom -i id -u oslandia
