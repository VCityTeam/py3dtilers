### See also
 - [Installation notes](Install.md)
 - [Developer's/Design notes](DesignNotes.md)
 
### Debugging temporary notes
Once [installed and ran](Install.md) and in order to 3D visulalize the results produced by the Tilers you might
 - install https://github.com/AnalyticalGraphicsInc/3d-tiles-samples
   and point the resulting junk directory holding the produced tileset
     cd 3d-tiles-samples
     ln -s ../py3dtiles.MEPP-team/junk .
   launch the server with npm start
   assert this is working by opening
      http://localhost:8003/junk/tileset.json
 - install UDV
 - patch UDV-Core/src/Setup3DScene.js and turn off temporal extension
   $3dTilesTemporalLayer.TemporalExtension = false
 - patch UDV-Core/examples/Demo.js and point buildingServerRequest
   const buildingServerRequest = 'http://localhost:8003/junk/tileset.json';
   install UDV and launch the server
 - view the results with your browser by opening
     http://localhost:8080/examples/Demo.html
   

### Credentials
This tiler original code is due to Jeremy Gaillard (and was realized
when working at LIRIS, University of Lyon, France)
