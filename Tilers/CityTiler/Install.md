## CityTiler quick installation notes

 1. Install py3Dtiles
    ```
    virtualenv -p python3 venv
    source venv/bin/activate
    pip install -e .
    python setup.py install
    ``` 
 2. Install the tiler specific dependency:
    ```
    pip install pyyaml
    ```
 3. Configure `Tilers/CityTiler/CityTilerDBConfig.yml` (out of Tilers/CityTiler/CityTilerDBConfigReference.yml` 
 4. from the home directory of the git
    * in order to run the CityTiler
      ```
      python Tilers/CityTiler/CityTiler.py --with_BTH Tilers/CityTiler/CityTilerDBConfig.yml 
      ```
      that (buy default) will create a `junk` ouput directory holding the resulting tile set,
    * in order to run the City**Temporal**Tiler you will first need to obtain the so called [evolution difference files](https://github.com/MEPP-team/RICT/tree/master/ShellScripts/computeLyonCityEvolution) between various temporal vintages. Let us assume such difference files were computed (e.g. with [computeLyonCityEvolution.sh](https://github.com/MEPP-team/RICT/blob/master/ShellScripts/computeLyonCityEvolution/computeLyonCityEvolution.sh)) in between three time stamps (2009, 20912, 2015) and for two buroughs (`LYON_1ER` and `LYON_2EME`). Then the invocation of the `CityTemporalTiler` goes 
      ```
      python Tilers/CityTiler/CityTemporalTiler.py                 \
      --db_config_path Tilers/CityTiler/CityTilerDBConfig2009.yml  \
                       Tilers/CityTiler/CityTilerDBConfig2012.yml  \
                       Tilers/CityTiler/CityTilerDBConfig2015.yml  \
      --time_stamp 2009 2012 2015                                  \
      --temporal_graph LYON_1ER_2009-2012/DifferencesAsGraph.json  \
                       LYON_1ER_2012-2015/DifferencesAsGraph.json  \
                       LYON_2EME_2009-2012/DifferencesAsGraph.json \
                       LYON_2EME_2012-2015/DifferencesAsGraph.json
      ```
