# -*- coding: utf-8 -*-
import os
import re
import sys
import platform

import setuptools
from setuptools import setup, find_packages
from setuptools.command.install import install
from setuptools.command.develop import develop
from setuptools.command.egg_info import egg_info

# For IfcOpenShell
import sysconfig
import zipfile
import urllib.request

here = os.path.abspath(os.path.dirname(__file__))

requirements = (
    'networkx',
    'numpy <1.21,>=1.17',
    'psycopg2',
    'pyproj',
    'pywavefront',
    'pyyaml',
    'scipy',
    'shapely',
    'alphashape',
    'py3dtiles @ git+https://github.com/VCityTeam/py3dtiles@Tiler',
    'earclip @ git+https://github.com/lionfish0/earclip',
    'Pillow'
    # 'ifcopenshell' requires specific treatment, refer to
    # install_ifcopenshell_from_url() function definition.
)

dev_requirements = (
    'flake8',
    'line_profiler',
    'pytest',
    'pytest-cov',
    'autopep8',
    'pytest-flake8',
    'pdoc3'
)

prod_requirements = (
)

# ### Specific for IFCOpenShell whose offered bundles (zip files) do NOT
# comme with a setup.py file (and hence cannot be pointed to in instal_requires)


def install_ifcopenshell_from_url():
    ifc_url = dict()
    ifc_url['Darwin'] = {
        '3.6': 'https://s3.amazonaws.com/ifcopenshell-builds/ifcopenshell-python-36-v0.6.0-517b819-macos64.zip',
        '3.7': 'https://s3.amazonaws.com/ifcopenshell-builds/ifcopenshell-python-37-v0.6.0-517b819-macos64.zip',
        '3.8': 'https://s3.amazonaws.com/ifcopenshell-builds/ifcopenshell-python-38-v0.6.0-517b819-macos64.zip',
        '3.9': 'https://s3.amazonaws.com/ifcopenshell-builds/ifcopenshell-python-39-v0.6.0-517b819-macos64.zip'
    }
    ifc_url['Linux'] = {
        '3.6': 'https://s3.amazonaws.com/ifcopenshell-builds/ifcopenshell-python-36-v0.6.0-517b819-linux64.zip',
        '3.7': 'https://s3.amazonaws.com/ifcopenshell-builds/ifcopenshell-python-37-v0.6.0-517b819-linux64.zip',
        '3.8': 'https://s3.amazonaws.com/ifcopenshell-builds/ifcopenshell-python-38-v0.6.0-517b819-linux64.zip',
        '3.9': 'https://s3.amazonaws.com/ifcopenshell-builds/ifcopenshell-python-39-v0.6.0-517b819-linux64.zip'
    }
    ifc_url['Windows'] = {
        '3.6': 'https://s3.amazonaws.com/ifcopenshell-builds/ifcopenshell-python-36-v0.6.0-517b819-win64.zip',
        '3.7': 'https://s3.amazonaws.com/ifcopenshell-builds/ifcopenshell-python-37-v0.6.0-517b819-win64.zip',
        '3.8': 'https://s3.amazonaws.com/ifcopenshell-builds/ifcopenshell-python-38-v0.6.0-517b819-win64.zip',
        '3.9': 'https://s3.amazonaws.com/ifcopenshell-builds/ifcopenshell-python-39-v0.6.0-517b819-win64.zip'
    }
    python_version = str(sys.version_info.major) + '.' + str(sys.version_info.minor)
    platform_name = platform.system()
    if platform_name not in ifc_url:
        print(f'{platform_name} not configured yet for this setup. Exiting.')
        sys.exit(1)
    try:
        url = ifc_url[platform_name][python_version]
    except:
        print(f'Unfound url for {python_version} and {platform_name}. Exiting')
        print(ifc_url[platform_name])
        sys.exit(1)
    temp_file_name = os.path.basename(url)
    with urllib.request.urlopen(url) as response, open(temp_file_name, 'wb') as out_file:
        data = response.read()  # a `bytes` object
        out_file.write(data)
    site_packages_dir = sysconfig.get_paths()["purelib"]
    with zipfile.ZipFile(temp_file_name, 'r') as zip_ref:
        zip_ref.extractall(site_packages_dir)
    if os.path.exists(temp_file_name):
        os.remove(temp_file_name)
    # Because of
    # https://stackoverflow.com/questions/59965769/print-a-message-from-setup-py-through-pip
    # the following print is only displayed when using `pip install . -v`
    print('Successfully installed IfcOpenShell.')

# Refer to
# https://stackoverflow.com/questions/19569557/pip-not-picking-up-a-custom-install-cmdclass
# for the reasons on having to decline the customizations
# FIXME: there is room for avoid a multiple install when e.g. both the install
# and egg_info get called by pip (in which case ifcopenshell gets downloaded,
# and unzipped twice)


class CustomInstallCommand(install):
    """Custom install command."""

    def run(self):
        install_ifcopenshell_from_url()
        install.run(self)


class CustomDevelopCommand(develop):
    def run(self):
        install_ifcopenshell_from_url()
        develop.run(self)


class CustomEggInfoCommand(egg_info):
    def run(self):
        install_ifcopenshell_from_url()
        egg_info.run(self)


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
    cmdclass={
        'install': CustomInstallCommand,
        'develop': CustomDevelopCommand,
        'egg_info': CustomEggInfoCommand,
    },
    classifiers=[
        'Development Status :: 3 - Alpha',
        'Intended Audience :: Developers',
        'Programming Language :: Python :: 3.5',
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
                            'obj-tiler=py3dtilers.ObjTiler:main'],
    },
    data_files=[('py3dtilers/CityTiler',
                 ['py3dtilers/CityTiler/CityTilerDBConfigReference.yml']
                 ),
                ('py3dtilers/Color',
                 ['py3dtilers/Color/default_config.json']
                )],
    zip_safe=False  # zip packaging conflicts with Numba cache (#25)
)
