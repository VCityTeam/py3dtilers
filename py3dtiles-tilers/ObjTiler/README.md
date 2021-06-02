### See also
 - [Installation notes](Install.md)
 - [Developer's/Design notes](DesignNotes.md)
 
### Running the ObjTiler

```
(venv) python Tilers/ObjTiler/ObjTiler.py  $PATH
```
$PATH should point to a directory holding a set of OBJ files. The resulting 3DTiles tileset
will contain all of the Obj that are in the directory, using their filename as 
ID. 

This command should produce a directory named "obj_tilesets"

### Debugging temporary notes
Once [installed and ran](Install.md) and in order to 3D visulalize the results produced by the Tilers you might
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
   


