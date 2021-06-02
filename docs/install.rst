Install
-------

From sources
~~~~~~~~~~~~

To use py3dtiles from sources:

.. code-block:: shell

    $ apt install git python3 python3-pip virtualenv libopenblas-base liblas-c3
    $ git clone https://github.com/Oslandia/py3dtiles
    $ cd py3dtiles
    $ virtualenv -p /usr/bin/python3 venv
    $ . venv/bin/activate
    (venv)$ pip install -e .
    (venv)$ python setup.py install

If you wan to run unit tests:

.. code-block:: shell

    (venv)$ pip install pytest pytest-benchmark
    (venv)$ pytest
    ...
