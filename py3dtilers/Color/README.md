# Color

## JSON config file

The `ColorConfig` class uses JSON config files to define the default colors. Each color is defined by a __color code__:

- Hexadecimal: `"#FFFFFF"`
- RGB(A): `[1, 1, 1]` or `[255, 255, 255]`

The JSON file must contain the following fields:

### default_color

The default color is used for the features which don't have a color setted.

```bash
"default_color": [1, 1, 1]
```

### min_color

The minimal color is minimal color of the [heatmap](https://en.wikipedia.org/wiki/Heat_map). This color corresponds to the lower values of the heatmap.

```bash
"min_color": [0, 1, 0]
```

### max_color

The maximal color is the maximal color of the [heatmap](https://en.wikipedia.org/wiki/Heat_map). This color corresponds to the higher values of the heatmap.

```bash
"max_color": [1, 0, 0]
```

### nb_colors

The number of colors is used to create the colors of the [heatmap](https://en.wikipedia.org/wiki/Heat_map). It corresponds to the number of colors between the [min_color](#min_color) and the [max_color](#max_color).

```bash
"nb_colors": 20
```

### color_dict

The color dictionary is used to match colors with attribute values. Each attribute value must be a key of the dictionary. A key `default` should be present for features which don't have a value for the targeted attribute (or have a value not present in the dictionary).

```bash
"color_dict": {
    "office": [1, 0, 0],
    "store": [0, 1, 0],
    "residential": [0, 0, 1],
    "default": [0.5, 0.5, 0.5]
}
```

## Use the ColorConfig class

To create a `ColorConfig` instance, use:

```bash
color_config = ColorConfig()
```

It will load the [_default_config.json_](./default_config.json). You can use another config file with:

```bash
color_config = ColorConfig("path/to/config.json")
```

Once the `ColorConfig` is created, you can get colored materials:

### By default

```bash
mat = color_config.get_default_color()
```

### By key

```bash
key = "office"
mat = color_config.get_color_by_key(key)
```

### By lerp

```bash
factor = 0.7
mat = color_config.get_color_by_lerp(factor)
```
