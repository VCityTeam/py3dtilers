# -*- coding: utf-8 -*-

# Note: order matters and must respect the dependency (e.g. inheritance) tree
from .schema_validators import SchemaValidators
from .extension import Extension
# When Tile becomes a ThreeDTilesNotion move this line afterwards
from .tile import Tile
from .threedtiles_notion import ThreeDTilesNotion
from .b3dm import B3dm
from .batch_table import BatchTable
from .batch_table_hierarchy_extension import BatchTableHierarchy
from .bounding_volume import BoundingVolume
from .bounding_volume_box import BoundingVolumeBox
from .feature_table import Feature
from .gltf import GlTF
from .real_tile import TileForReal
from .tileset import TileSet
from .helper_test import HelperTest
from .pnts import Pnts
from .utils import TileReader, convert_to_ecef
from .wkb_utils import TriangleSoup

__version__ = '1.1.0'
__all__ = ['B3dm',
           'BatchTable', 
           'BatchTableHierarchy', 
           'BoundingVolume',
           'BoundingVolumeBox',
           'convert_to_ecef', 
           'SchemaValidators',
           'Extension',
           'Feature', 
           'GlTF', 
           'Pnts',
           'TileForReal', 
           'Tile', 
           'TileReader', 
           'TileSet',
           'ThreeDTilesNotion',
           'TriangleSoup']
