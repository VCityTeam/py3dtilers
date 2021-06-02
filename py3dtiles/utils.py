# -*- coding: utf-8 -*-

import numpy as np
import pyproj
from .pnts import Pnts
from .b3dm import B3dm


def convert_to_ecef(x, y, z, epsg_input):
    inp = pyproj.Proj(init='epsg:{0}'.format(epsg_input))
    outp = pyproj.Proj(init='epsg:4978')  # ECEF
    return pyproj.transform(inp, outp, x, y, z)


class TileReader(object):

    def read_file(self, filename):
        with open(filename, 'rb') as f:
            data = f.read()
            arr = np.frombuffer(data, dtype=np.uint8)
            return self.read_array(arr)
        return None

    def read_array(self, array):
        magic = ''.join([c.decode('UTF-8') for c in array[0:4].view('c')])
        if magic == 'pnts':
            return Pnts.from_array(array)
        if magic == 'b3dm':
            return B3dm.from_array(array)
        return None
