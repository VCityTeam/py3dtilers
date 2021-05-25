# -*- coding: utf-8 -*-
import os
import re
from setuptools import setup, find_packages

here = os.path.abspath(os.path.dirname(__file__))

requirements = (
    'numpy',
    'pyproj',
    'cython',
    'triangle',
    'psycopg2-binary',
    'liblas',
    'laspy',
    'numba',
    'pyproj',
    'psutil',
    'lz4',
    'pyzmq',
    'jsonschema',
    'pywavefront',
    'scipy'
)

dev_requirements = (
    'pytest',
    'pytest-cov',
    'pytest-benchmark',
    'line_profiler'
)

doc_requirements = (
    'sphinx',
    'sphinx_rtd_theme',
)

prod_requirements = (
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
    name='py3dtiles',
    version=find_version('py3dtiles', '__init__.py'),
    description="Python module for 3D tiles format",
    long_description=read('README.rst'),
    url='https://github.com/Oslandia/py3dtiles',
    author='Oslandia',
    author_email='contact@oslandia.com',
    license='Apache License Version 2.0',
    classifiers=[
        'Development Status :: 3 - Alpha',
        'Intended Audience :: Developers',
        'Programming Language :: Python :: 3.4',
        'Programming Language :: Python :: 3.5',
    ],
    packages=find_packages(),
    install_requires=requirements,
    test_suite="tests",
    extras_require={
        'dev': dev_requirements,
        'prod': prod_requirements,
        'doc': doc_requirements
    },
    entry_points={
        'console_scripts': ['py3dtiles=py3dtiles.command_line:main'],
    },
    data_files=[('py3dtiles/jsonschemas',
                   [ 'py3dtiles/jsonschemas/3DTILES_batch_table_hierarchy.json',
                     'py3dtiles/jsonschemas/3DTILES_temporal.batchTable.schema.json',
                     'py3dtiles/jsonschemas/3DTILES_temporal.boundingVolume.schema.json',
                     'py3dtiles/jsonschemas/3DTILES_temporal.tileset.schema.json',
                     'py3dtiles/jsonschemas/3DTILES_temporal.transaction.schema.json',
                     'py3dtiles/jsonschemas/3DTILES_temporal.primaryTransaction.schema.json',
                     'py3dtiles/jsonschemas/3DTILES_temporal.transactionAggregate.schema.json',
                     'py3dtiles/jsonschemas/3DTILES_temporal.version.schema.json',
                     'py3dtiles/jsonschemas/3DTILES_temporal.versionTransition.schema.json',
                     'py3dtiles/jsonschemas/batchTable.schema.json',
                     'py3dtiles/jsonschemas/boundingVolume.schema.json',
                     'py3dtiles/jsonschemas/extension.schema.json',
                     'py3dtiles/jsonschemas/extras.schema.json',
                     'py3dtiles/jsonschemas/properties.schema.json',
                     'py3dtiles/jsonschemas/tile.schema.json',
                     'py3dtiles/jsonschemas/tile.content.schema.json',
                     'py3dtiles/jsonschemas/tileset.schema.json' ]
                )], 
    zip_safe=False  # zip packaging conflicts with Numba cache (#25)
)
