import unittest
import numpy as np
from py3dtiles import B3dm, GlTF, TriangleSoup

class TestTileBuilder(unittest.TestCase):

    def test_build(self):
        ts = TriangleSoup()
        trianglesArray = [[
           [ np.array([ 36.99783, 234.92761, 176.9191 ], dtype=float),
             np.array([ 40.09393, 237.59793, 190.9191 ], dtype=float),
             np.array([ 50.99783, 254.92761, 208.97176], dtype=float) ]
        ]]
        ts.triangles = trianglesArray
        positions = ts.getPositionArray()
        normals = ts.getNormalArray()
        # Box is [[minX, minY, minZ],[maxX, maxY, maxZ]] expressed as floats (not binaires):
        box = [[float(i) for i in j] for j in ts.getBbox()]
        center = [(box[0][i] + box[1][i]) / 2 for i in range(0,3)]
        xAxis = [box[1][0] - box[0][0], 0,                     0]
        yAxis = [0,                     box[1][1] - box[0][1], 0]
        zAxis = [0,                     0,                     box[1][2] - box[0][2]]
        bounding_volume = [ round(x, 3) for x in center + xAxis + yAxis + zAxis ]
                            
        ## print("aaaaaaaaaaaaaaaaaaaaaaaaaaaa", bounding_volume)
        arrays = [{
            'position': positions,
            'normal': normals,
            'bbox': box
        }]

        transform = np.array([
            [1, 0, 0, 1842015.125],
            [0, 1, 0, 5177109.25],
            [0, 0, 1, 247.87364196777344],
            [0, 0, 0, 1]], dtype=float)
        # translation : 1842015.125, 5177109.25, 247.87364196777344
        transform = transform.flatten('F')
        glTF = GlTF.from_binary_arrays(arrays, transform)
        t = B3dm.from_glTF(glTF)
        t.save_as("junko_test_tile_1.b3dm")
