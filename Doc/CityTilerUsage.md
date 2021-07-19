# CityTiler (probably outdated) usage notes


#### 4/ Configure the database description file
You can customize the [CityTilerDBConfigReference.yml](../py3dtilers/CityTiler/CityTilerDBConfigReference.yml) reference file:
```
(venv) pushd Tilers/CityTiler
(venv) cp CityTilerDBConfigReference.yml CityTilerDBConfig.yml
```
Edit `CityTilerDBConfig.yml` and proceed with the configuration specification
by giving the information required to access the 3DCityDB. 
Change working directory back to home of py3dtiles git clone
``` 
(venv) popd       # Refer to above pushd
``` 

#### 5a/ Running the CityTiler
From the **home directory** (and you have to) of your py3dtiles git clone, run 
```
(venv) python Tilers/CityTiler/CityTiler.py --with_BTH Tilers/CityTiler/CityTilerDBConfig.yml 
```
By default this command will create a `junk` ouput directory holding both 
 * the resulting tile set file (with the .json extension) and 
 * a `tiles` folder containing the associated set of `.b3dm` files
 
*Note that the tiler must be launched from the root of py3dtiles, because of [this assumption](https://github.com/MEPP-team/py3dtiles/blob/Tiler/py3dtiles/schema_with_sample.py#L48). Otherwise you will get an error in the form `Unfound schema file batchTable.schema.json`*

#### 5b/ Running the temporal version City**Temporal**Tiler
In order to run the City**Temporal**Tiler you will first need to obtain the so called [evolution difference files](https://github.com/MEPP-team/RICT/tree/master/ShellScripts/computeLyonCityEvolution) between various temporal vintages. Let us assume such difference files were computed (e.g. with [computeLyonCityEvolution.sh](https://github.com/MEPP-team/RICT/blob/master/ShellScripts/computeLyonCityEvolution/ShellScript/computeLyonCityEvolution.sh)) in between three time stamps (2009, 2012, 2015) and for two boroughs (`LYON_1ER` and `LYON_2EME`). Then the invocation of the `CityTemporalTiler` goes **from the home directory**:
```
python Tilers/CityTiler/CityTemporalTiler.py                   \
  --db_config_path Tilers/CityTiler/CityTilerDBConfig2009.yml  \
                   Tilers/CityTiler/CityTilerDBConfig2012.yml  \
                   Tilers/CityTiler/CityTilerDBConfig2015.yml  \
  --time_stamp 2009 2012 2015                                  \
  --temporal_graph LYON_1ER_2009-2012/DifferencesAsGraph.json  \
                   LYON_1ER_2012-2015/DifferencesAsGraph.json  \
                   LYON_2EME_2009-2012/DifferencesAsGraph.json \
                   LYON_2EME_2012-2015/DifferencesAsGraph.json
```

*Note that the tiler must be launched from the root of py3dtiles, because of [this assumption](https://github.com/MEPP-team/py3dtiles/blob/Tiler/py3dtiles/schema_with_sample.py#L48). Otherwise you will get an error in the form `Unfound schema file batchTable.schema.json`*

### OBSELETE: Visualizing the resulting tileset (debugging temporary notes)

Once installed and ran <!--[installed and ran](Install.md)--> and in order to 3D visulalize the results produced by the Tilers you might
* install https://github.com/AnalyticalGraphicsInc/3d-tiles-samples
  and point the resulting junk directory holding the produced tileset
  
  ```bash
     cd 3d-tiles-samples
     ln -s ../py3dtiles.MEPP-team/junk .
  ```

  launch the server with `npm start` and assert this is working by opening 
  `http://localhost:8003/junk/tileset.json`
* install UDV
* patch UDV-Core/src/Setup3DScene.js and turn off temporal extension
   $3dTilesTemporalLayer.TemporalExtension = false
* patch UDV-Core/examples/Demo.js and point buildingServerRequest
   const buildingServerRequest = 'http://localhost:8003/junk/tileset.json';
   install UDV and launch the server
* view the results with your browser by opening
  `http://localhost:8080/examples/Demo.html`

### Developer's note
If you happen to modify the core of py3dtiles (that is any file in the `py3dtiles/py3dtiles/` subdirectory) then prior to running any script using Py3DTiles (e.g. a Tiler or export_tileset) you will need to re-install Py3DTiles for changes to be considered. The commands are then
```
pip uninstall py3dtiles     # Just to avoid pycache trouble
pin install ./py3dtiles     # Equivalent of `pip install -e .`
``` 
