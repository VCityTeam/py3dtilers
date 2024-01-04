# -*- coding: utf-8 -*-
import os
import re
from setuptools import setup, find_packages


here = os.path.abspath(os.path.dirname(__file__))

requirements = (
    'wheel',
    'numpy',
    'psycopg2',
    'pyproj',
    'pywavefront',
    'pyyaml',
    'scipy==1.9.3',
    'shapely',
    'alphashape',
    'py3dtiles @ git+https://github.com/VCityTeam/py3dtiles@Tiler',
    'earclip @ git+https://github.com/lionfish0/earclip',
    'Pillow',
    'ifcopenshell',
    'sortedcollections', 
    'triangle'
)

dev_requirements = (
    'flake8',
    'line_profiler',
    'pytest',
    'pytest-cov',
    'autopep8',
    'pdoc3'
)

prod_requirements = (
    'testing.postgresql @ git+https://github.com/tk0miya/testing.postgresql'
)


def read(fname):
    return open(os.path.join(os.path.dirname(__file__), fname)).read()


def find_version(*file_paths):
    """
    see https://github.com/pypa/sampleproject/blob/master/setup.py
    """

    with open(os.path.join(here, *file_paths), 'r') as f:
        version_file = f.read()

    # The version line must have the form
    # __version__ = 'ver'
    version_match = re.search(r"^__version__ = ['\"]([^'\"]*)['\"]",
                              version_file, re.M)
    if version_match:
        return version_match.group(1)
    raise RuntimeError("Unable to find version string. "
                       "Should be at the first line of __init__.py.")


setup(
    name='py3dtilers',
    version=find_version('py3dtilers', '__init__.py'),
    description="Python module for computing 3D tiles",
    long_description=read('README.md'),
    url='https://github.com/VCityTeam/py3dtilers',
    author='Université de Lyon',
    author_email='contact@liris.cnrs.fr',
    license='Apache License Version 2.0',
    python_requires=">=3.8,<=3.11",
    classifiers=[
        'Development Status :: 3 - Alpha',
        'Intended Audience :: Developers',
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11"

    ],
    packages=find_packages(),
    install_requires=requirements,
    test_suite="tests",
    extras_require={
        'dev': dev_requirements,
        'prod': prod_requirements
    },
    entry_points={
        'console_scripts': ['citygml-tiler=py3dtilers.CityTiler:main',
                            'geojson-tiler=py3dtilers.GeojsonTiler:main',
                            'ifc-tiler=py3dtilers.IfcTiler:main',
                            'citygml-tiler-temporal=py3dtilers.CityTiler:main_temporal',
                            'obj-tiler=py3dtilers.ObjTiler:main',
                            'tileset-reader=py3dtilers.TilesetReader:main',
                            'tileset-merger=py3dtilers.TilesetReader:merger_main'],
    },
    data_files=[('py3dtilers/CityTiler',
                 ['py3dtilers/CityTiler/CityTilerDBConfigReference.yml']
                 ),
                ('py3dtilers/Color',
                 ['py3dtilers/Color/default_config.json']
                 ),
                ('py3dtilers/Color',
                 ['py3dtilers/Color/citytiler_config.json']
                 )],
    zip_safe=False  # zip packaging conflicts with Numba cache (#25)
)
