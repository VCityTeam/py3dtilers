import unittest
from argparse import Namespace
from pathlib import Path

from py3dtilers.IfcTiler.IfcTiler import IfcTiler


def get_default_namespace():
    return Namespace(obj=None, loa=None, lod1=False, crs_in='EPSG:3946',
                     crs_out='EPSG:3946', offset=[0, 0, 0], with_texture=False, grouped_by='IfcTypeObject', scale=1,
                     output_dir=None, geometric_error=[None, None, None], kd_tree_max=None)


class Test_Tile(unittest.TestCase):

    def test_IFC4_case(self):
        path = Path('tests/ifc_tiler_test_data/FZK.ifc')
        ifc_tiler = IfcTiler()
        ifc_tiler.args = get_default_namespace()
        ifc_tiler.args.output_dir = Path("tests/ifc_tiler_test_data/generated_tilesets/")

        tileset = ifc_tiler.from_ifc(path, ifc_tiler.args.grouped_by)
        if(tileset is not None):
            tileset.write_as_json(ifc_tiler.args.output_dir)


if __name__ == '__main__':
    unittest.main()