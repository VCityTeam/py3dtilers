# Python 3DTiles Tilers

p3dtilers is a Python tool and library allowing to build [`3D Tiles`](https://github.com/AnalyticalGraphicsInc/3d-tiles) tilesets out of various geometrical formats e.g. [OBJ](https://en.wikipedia.org/wiki/Wavefront_.obj_file), [GeoJSON](https://en.wikipedia.org/wiki/GeoJSON), [IFC](https://en.wikipedia.org/wiki/Industry_Foundation_Classes) or [CityGML](https://en.wikipedia.org/wiki/CityGML) through [3dCityDB databases](https://3dcitydb-docs.readthedocs.io/en/release-v4.2.3/)

p3dtilers uses [`py3dtiles` python library](https://gitlab.com/Oslandia/py3dtiles) for its in memory representation of tilesets

**CLI** **Features**

* [ObjTiler](./py3dtilers/ObjTiler): converts OBJ files to a 3D Tiles tileset
* [GeojsonTiler](./py3dtilers/GeojsonTiler): converts GeoJson files to a 3D Tiles tileset
* [IfcTiler](./py3dtilers/IfcTiler): converts IFC files to a 3D Tiles tileset
* [CityTiler](./py3dtilers/CityTiler): converts CityGML features (e.g buildings, water bodies, terrain...) extracted from a 3dCityDB database to a 3D Tiles tileset

## Installation from sources

NB: py3dtilers installation requires a Bash shell. If you're using Windows 10, see how use the [Ubuntu Bash shell on Windows](https://www.howtogeek.com/249966/how-to-install-and-use-the-linux-bash-shell-on-windows-10/).

In order to install py3dtilers from sources use:

```bash
$ apt install git python3 python3-pip virtualenv
$ git clone https://github.com/VCityTeam/py3dtilers
$ cd py3dtilers
```

Install binary sub-dependencies with your platform package installer e.g. for Ubuntu use

```bash
$ apt-get install -y liblas-c3 libopenblas-base # py3dtiles binary dependencies
$ apt-get install -y libpq-dev                  # required usage of psycopg2 within py3dtilers
```

(_Warning_: when using Ubuntu 20.04, replace `liblas-c3` by `liblaszip-dev`)

Proceed with the installation of `py3dtilers` per se

```bash
$ virtualenv -p python3 venv
$ . venv/bin/activate
(venv)$ pip install -e .
```

(_Note_: On Windows (__without bash shell__), replace `$ . venv/bin/activate` with `$ . venv\Scripts\activate`)

**Caveat emptor**: make sure, that the IfcOpenShell dependency was properly installed with help of the `python -c 'import ifcopenshell'` command. In case
of failure of the importation try re-installing but this time with the verbose
flag, that is try

```bash
(venv)$ pip install -e . -v
```

and look for the lines concerning `IfcOpenShell.`

## Usage

To use the a tiler, check the corresponding readme to know the usage and the features of the tiler.

* CityTiler [readme](py3dtilers/CityTiler/README.md)
* GeojsonTiler [readme](py3dtilers/GeojsonTiler/README.md)
* ObjTiler [readme](py3dtilers/ObjTiler/README.md)
* IfcTiler [readme](py3dtilers/IfcTiler/README.md)

## Develop with py3dtilers

### Running the tests (optional)

After the installation, if you additionally wish to run unit tests, use

```bash
(venv)$ pip install -e .[dev]
(venv)$ pytest
```

To run CityTiler's tests, you need to install PostgreSQL and Postgis.

To setup PostgreSQL with Postgis on Windows, follow the first step (1. Download PostgreSQL/PostGIS) of [3DCityDB tutorial](https://github.com/VCityTeam/UD-SV/blob/master/ImplementationKnowHow/PostgreSQL_for_cityGML.md#1-download-postgresqlpostgis).  
For Ubuntu, follow [this tutorial](https://github.com/VCityTeam/UD-SV/blob/master/Install/Setup_PostgreSQL_PostGIS_Ubuntu.md).

Once the setup is over, update the config files (e.g [test_config.yml](tests/city_tiler_test_data/test_config.yml), [test_config_2009.yml](tests/city_temporal_tiler_test_data/test_config_2009.yml) and [test_config_2012.yml](tests/city_temporal_tiler_test_data/test_config_2012.yml)) with the right password. Ignore the config files to avoid commiting them in the repo

```bash
git update-index --assume-unchanged tests/*/test_config*
```

Then, in a shell, run:

```bash
> psql -c 'create database test_city_tiler;' -U postgres
> psql -U postgres -d test_city_tiler -f tests/city_tiler_test_data/test_data.sql
> psql -c 'create database test_temporal_2009;' -U postgres
> psql -U postgres -d test_temporal_2009 -f tests/city_temporal_tiler_test_data/test_data_temporal_2009.sql
> psql -c 'create database test_temporal_2012;' -U postgres
> psql -U postgres -d test_temporal_2012 -f tests/city_temporal_tiler_test_data/test_data_temporal_2012.sql
```

### Coding style

First, install the additional dev requirements

```bash
(venv)$ pip install -e .[dev]
```

To check if the code follows the coding style, run `flake8`

```bash
(venv)$ flake8 .
```

You can fix most of the coding style errors with `autopep8`

```bash
(venv)$ autopep8 --in-place --recursive py3dtilers/
```

If you want to apply `autopep8` from root directory, exclude the _venv_ directory

```bash
(venv)$ autopep8 --in-place --exclude='venv*' --recursive .
```

### Developing py3dtilers together with py3dtiles

By default, the py3dtilers' [`setup.py`](https://github.com/VCityTeam/py3dtilers/blob/master/setup.py#L30) build stage uses [github's version of py3dtiles](https://github.com/VCityTeam/py3dtiles) (as opposed to using [Oslandia's version on Pypi](https://pypi.org/project/py3dtiles/).
When developing one might need/wish to use a local version of py3dtiles (located on host in another directory e.g. by cloning the original repository) it is possible 
 1. to first install py3dtiles by following the [installation notes](https://github.com/Oslandia/py3dtiles/blob/master/docs/install.rst)
 2. then within the py3dtilers (cloned) directory, comment out (or delete) [the line reference to py3dtiles](https://github.com/VCityTeam/py3dtilers/blob/master/setup.py#L30).

This boils down to :
```bash
$ git clone https://github.com/VCityTeam/py3dtiles
$ cd py3dtiles
$ ...
$ source venv/bin/activate
(venv)$ cd ..
(venv)$ git clone https://github.com/VCityTeam/py3dtilers
(venv)$ cd py3dtilers
(venv)$ # Edit setup.py and comment out py3dtiles reference
(venv)$ pip install -e .
(venv)$ pytest
```

### Documentation

The documentation can be found in the [HTML](./html/py3dtilers/index.html) repository.

To update the documentation :

- assert that [Pdoc](https://pypi.org/project/pdoc3/) is installed
- run the following command in the root folder on this repo :
```bash
$ pdoc --html .\py3dtilers --force
```


### Concerning CityTiler

* For developers, some [design notes](Doc/CityTilerDesignNotes.md)
* Credentials: CityTiler original code is due to Jeremy Gaillard (when working at LIRIS, University of Lyon, France)
