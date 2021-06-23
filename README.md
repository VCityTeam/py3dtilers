# Python 3DTiles Tilers

p3dtilers is a Python tool and library allowing to build [`3D Tiles`](https://github.com/AnalyticalGraphicsInc/3d-tiles) tilesets out of various geometrical formats e.g. [OBJ](https://en.wikipedia.org/wiki/Wavefront_.obj_file), [GeoJSON](https://en.wikipedia.org/wiki/GeoJSON) or [CityGML through 3dCityDB databases](https://3dcitydb-docs.readthedocs.io/en/release-v4.2.3/)

p3dtilers uses [`py3dtiles` python library](https://gitlab.com/Oslandia/py3dtiles) for its in memory representation of tilesets

**CLI** **Features**

* Convert OBJ files to a 3D Tiles tileset
* Convert GeoJson files to a 3D Tiles tileset 
* Extract [CityGML](https://en.wikipedia.org/wiki/CityGML) features (e.g buildings, bridges, terrain...) from a [3dCityDB database](https://3dcitydb-docs.readthedocs.io/en/release-v4.2.3/) to a 3D Tiles tileset

## Installation from sources

In order to install py3dtilers from sources use:

```bash
$ apt install git python3 python3-pip virtualenv
$ git clone https://github.com/VCityTeam/py3dtilers
$ cd py3dtilers
```

Install `py3dtiles` sub-dependencies (`liblas`) with your platform package installer e.g. for Ubuntu use

```bash
$ apt-get install -y liblas-c3 libopenblas-base libpq-dev
```
(_Warning_: when using Ubuntu 20.04, replace `liblas-c3` by `liblaszip-dev`)

Proceed with the installation of `py3dtilers` per se

```bash
$ virtualenv -p python3 venv
$ . venv/bin/activate
(venv)$ pip install -e .
```

**Caveat emptor**: make sure, that the IfcOpenShell dependency was properly installed with help of the `python -c 'import ifcopenshell'` command. In case
of failure of the importation try re-installing but this time with the verbose
flag, that is try

```bash
(venv)$ pip install -e . -v
```

and look for the lines concerning `IfcOpenShell.`

### Running the tests (optional)

After the installation, if you additionally wish to run unit tests, use

```bash
(venv)$ pip install -e .[extra]
(venv)$ pip install pytest # Even if you already have pytest, re-install it to make sure pytest exists in venv
(venv)$ pytest
```

### Working with Py3DTiles

By default, the setup.py build refers to the online github of py3DTiles.
If one want to work with a local py3DTiles, intall py3DTiles by following the [installation notes](https://github.com/Oslandia/py3dtiles/blob/master/docs/install.rst)
Then, in the py3dtilers repository, comment or delete [this](https://github.com/VCityTeam/py3dtilers/blob/master/setup.py#L30) line, that link the py3dtiles github with py3dtilers.

Use :
`(venv)$ cd PATH_TO_py3dtilers`
`(venv)$ pip install -e .`


## CLI Usage

### Concerning CityTiler

* CityTiler [usage documentation](Doc/CityTilerUsage.md)
* For developers, some [design notes](Doc/CityTilerDesignNotes.md)
* Credentials: CityTiler original code is due to Jeremy Gaillard (when working at LIRIS, University of Lyon, France)
