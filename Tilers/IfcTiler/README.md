### See also
 - [Installation notes](Install.md)
 - [Developer's/Design notes](DesignNotes.md)


### Intallation note (temporary) : 

This tiler needs more packages (that needs to be in the setup.py) : 

- To install [numpy](https://numpy.org/)
```
(venv) pip install numpy
```

- To install [pyproj](https://pypi.org/project/pyproj/)
```
(venv) pip install pyproj
```

- To install [IfcOpenShell](http://ifcopenshell.org/)
    - Download the archive of the binary [here](http://ifcopenshell.org/python)
    - Use the following command to find the site-packages folder of your Python distribution ```python -m site --user-site```
    - Place it the extracted archive


### Running the IfcTiler

```
(venv) python Tilers/IfcTiles/IfcTiler.py  $PATH
```
$PATH should point to a directory holding an IFC file. 
The resulting 3DTiles tileset will contain the ifc geometry, ordered by category :
each tile will contain an IFC Object Type, that can be found in the batch table, along with its GUID 

This command should produce a directory named "ifc_tileset"


### About the tiler : 

- Projection system conversion using Pyproj : 
    - Actually "EPSG:27562" to "EPSG:3946" to support our test
    - Needs to be used in CL

- Scale change of the geometry : 
    - Actually, we can change from centimeter to meter
    - Needs to be used or not in CL
    - Needs to accept more units

- Support only IFC4 :
    - needs to support IFC2XC3 : 
            - test the file version
            - change the geometry access 

- Support the following geomtry types, ignore other types : 
    - MappedRepresentation
    - Tesselation
    - SweptSolid

- All object position are relative to the site position (the higher node in the hierarchy ifc file). The position of the site is put in the transform field of the tileset.json of the generated 3DTiles, meaning that we can easily change the IFC position directly in the tileset.json file.


### Debugging temporary notes
Once [installed and ran](Install.md) and in order to 3D visualize the results produced by the Tilers you might
 - install https://github.com/AnalyticalGraphicsInc/3d-tiles-samples
   and point the resulting junk directory holding the produced tileset
```
     cd 3d-tiles-samples
     ln -s ../py3dtiles.MEPP-team/junk .
```
   launch the server with ```npm start```
   assert this is working by opening
      http://localhost:8003/junk/tileset.json
 - install [UD-Viz](https://github.com/VCityTeam/UD-Viz)
 - patch UDV-Core/examples/Demo.js and point buildingServerRequest
   const buildingServerRequest = 'http://localhost:8003/junk/tileset.json';
   install UDV and launch the server
 - view the results with your browser by opening
     http://localhost:8080/examples/Demo.html