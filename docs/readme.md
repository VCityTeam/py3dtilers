# Documentation

The documentation can be found in the [HTML](./py3dtilers/index.html) repository.

To update the documentation :

- assert that [Pdoc](https://pypi.org/project/pdoc3/) is installed using:

```bash
pip install -e .[dev]
```

- run the following command in the root folder on this repo:

```bash
pdoc --html ./py3dtilers -o ./docs --force
```

The produced documentation should be in the ./docs/py3dtilers repository.

## Tips

- This file is considered as the entry point for github pages : there is a redirection to the index.html file at the end.

<script>window.onload = function() {
    location.href = "./py3dtilers/index.html";
}</script>
