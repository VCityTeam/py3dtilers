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
$ apt-get install -y liblas-c3 libopenblas-base
```

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
(venv)$ pytest
```

## CLI Usage

### Concerning CityTiler

* CityTiler [usage documentation](Doc/CityTilerUsage.md)
* For developers, some [design notes](Doc/CityTilerDesignNotes.md)
* Credentials: CityTiler original code is due to Jeremy Gaillard (when working at LIRIS, University of Lyon, France)
