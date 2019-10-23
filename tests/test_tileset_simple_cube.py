import unittest
import numpy as np
from py3dtiles import B3dm, GlTF, TriangleSoup, TileSet, Tile


class TestTileBuilder(unittest.TestCase, object):

    @staticmethod
    def build_cuboid_as_binary_triangles_array(org_x, org_y, org_z, dx, dy, dz):
        # The following Cuboid definition assumes a z-up coordinate system.
        # Vertices order is such that normals are pointing outwards of the cube.
        # Each face of the cube is made of two triangles.
        return [
            # Lower face (parallel to Ox-Oy plane i.e. horizontal)
            [np.array([org_x + dx, org_y,      org_z     ], dtype=np.float32),
             np.array([org_x     , org_y,      org_z     ], dtype=np.float32),
             np.array([org_x + dx, org_y + dy, org_z     ], dtype=np.float32)],
            [np.array([org_x,      org_y,      org_z     ], dtype=np.float32),
             np.array([org_x,      org_y + dy, org_z     ], dtype=np.float32),
             np.array([org_x + dx, org_y + dy, org_z     ], dtype=np.float32)],
            # Upper face (parallel to Ox-Oy plane i.e. horizontal)
            [np.array([org_x,      org_y,      org_z + dz], dtype=np.float32),
             np.array([org_x + dx, org_y,      org_z + dz], dtype=np.float32),
             np.array([org_x + dx, org_y + dy, org_z + dz], dtype=np.float32)],
            [np.array([org_x,      org_y + dy, org_z + dz], dtype=np.float32),
             np.array([org_x,      org_y,      org_z + dz], dtype=np.float32),
             np.array([org_x + dx, org_y + dy, org_z + dz], dtype=np.float32)],
            # Side face parallel to the Ox-Oz plane (vertical),
            [np.array([org_x,      org_y,      org_z     ], dtype=np.float32),
             np.array([org_x + dx, org_y,      org_z     ], dtype=np.float32),
             np.array([org_x + dx, org_y,      org_z + dz], dtype=np.float32)],
            [np.array([org_x,      org_y,      org_z     ], dtype=np.float32),
             np.array([org_x + dx, org_y,      org_z + dz], dtype=np.float32),
             np.array([org_x,      org_y,      org_z + dz], dtype=np.float32)],
            # Other side face parallel to the Ox-Oz plane,
            [np.array([org_x,      org_y + dy, org_z     ], dtype=np.float32),
             np.array([org_x + dx, org_y + dy, org_z + dz], dtype=np.float32),
             np.array([org_x + dx, org_y + dy, org_z     ], dtype=np.float32)],
            [np.array([org_x,      org_y + dy, org_z     ], dtype=np.float32),
             np.array([org_x,      org_y + dy, org_z + dz], dtype=np.float32),
             np.array([org_x + dx, org_y + dy, org_z + dz], dtype=np.float32)],
            # Side face parallel to the Oy-Oz plane (vertical)
            [np.array([org_x,      org_y,      org_z     ], dtype=np.float32),
             np.array([org_x,      org_y,      org_z + dz], dtype=np.float32),
             np.array([org_x,      org_y + dy, org_z + dz], dtype=np.float32)],
            [np.array([org_x,      org_y,      org_z     ], dtype=np.float32),
             np.array([org_x,      org_y + dy, org_z + dz], dtype=np.float32),
             np.array([org_x,      org_y + dy, org_z     ], dtype=np.float32)],
            # Other side face parallel to the Oy-Oz plane (vertical)
            [np.array([org_x + dx, org_y,      org_z     ], dtype=np.float32),
             np.array([org_x + dx, org_y + dy, org_z + dz], dtype=np.float32),
             np.array([org_x + dx, org_y,      org_z + dz], dtype=np.float32)],
            [np.array([org_x + dx, org_y,      org_z     ], dtype=np.float32),
             np.array([org_x + dx, org_y + dy, org_z     ], dtype=np.float32),
             np.array([org_x + dx, org_y + dy, org_z + dz], dtype=np.float32)],
        ]

    def test_build(self):
        # Define a TriangleSoup setting up some geometry
        ts = TriangleSoup()
        triangles = TestTileBuilder.build_cuboid_as_binary_triangles_array(
                                    -178.1, -12.845, 300.0, 100., 200., 300.)
        triangles.extend(
                    TestTileBuilder.build_cuboid_as_binary_triangles_array(
                                      -8.1, -1.8, 300.0, 200., 300., 100.))
        ts.triangles = [triangles]

        # Define a tile that will hold the geometry
        tile = Tile()
        tile.set_bounding_volume(ts.getBoxBoundingVolumeAlongAxis())

        # Build a tile content (with B3dm formatting) out of the geometry
        # held in the TriangleSoup:
        arrays = [{
            'position': ts.getPositionArray(),
            'normal':   ts.getNormalArray(),
            'bbox':     ts.getBboxAsFloat()
        }]
        # GlTF uses a y-up coordinate system, and we thus need to realize
        # a z-up to y-up coordinate transform for the cuboids to respect
        # glTF convention (refer to
        # https://github.com/AnalyticalGraphicsInc/3d-tiles/tree/master/specification#gltf-transforms
        # for more details on this matter).
        transform = np.array([ 1,  0,  0, 0,
                               0,  0, -1, 0,
                               0,  1,  0, 0,
                               0,  0,  0, 1])
        glTF = GlTF.from_binary_arrays(arrays, transform)
        tile_content = B3dm.from_glTF(glTF)
        tile.set_content(tile_content)

        # Define the TileSet that will hold the (single) tile
        tile_set = TileSet()
        # Hardwiring :-( a translation of this TileSet to the coordinates of
        # the city of Lyon in EPSG:3946 refer to
        # https://epsg.io/map#srs=3946&x=1841276.446781&y=5172616.229943&z=14&layer=streets
        tile_set.set_transform([1, 0, 0, 0,
                                0, 1, 0, 0,
                                0, 0, 1, 0,
                                1841276.4464434995, 5172616.229383407, 0, 1])

        tile_set.set_root_tile(tile)
        tile_set.add_asset_extras("Py3dTiles TestTileBuilder example.")
        tile_set.write_to_directory('junk')
