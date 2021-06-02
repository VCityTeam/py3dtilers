# -*- coding: utf-8 -*-

import json
from enum import Enum
import numpy as np


class Feature(object):

    def __init__(self):
        self.positions = {}
        self.colors = {}

    def to_array(self):
        pos_arr = np.array([(self.positions['X'], self.positions['Y'],
                            self.positions['Z'])]).view(np.uint8)[0]

        if len(self.colors):
            col_arr = np.array([(self.colors['Red'], self.colors['Green'],
                                self.colors['Blue'])]).view(np.uint8)[0]
        else:
            col_arr = np.array([])

        return [pos_arr, col_arr]

    @staticmethod
    def from_values(x, y, z, red=None, green=None, blue=None):
        f = Feature()

        f.positions = {'X': x, 'Y': y, 'Z': z}

        if red or green or blue:
            f.colors = {'Red': red, 'Green': green, 'Blue': blue}
        else:
            f.colors = {}

        return f

    @staticmethod
    def from_array(positions_dtype, positions, colors_dtype=None, colors=None):
        """
        Parameters
        ----------
        positions_dtype : numpy.dtype

        positions : numpy.array
            Array of uint8.

        colors_dtype : numpy.dtype

        colors : numpy.array
            Array of uint8.

        Returns
        -------
        f : Feature
        """

        f = Feature()

        # extract positions
        f.positions = {}
        off = 0
        for d in positions_dtype.names:
            dt = positions_dtype[d]
            data = np.array(positions[off:off+dt.itemsize]).view(dt)[0]
            off += dt.itemsize
            f.positions[d] = data

        # extract colors
        f.colors = {}
        if colors_dtype is not None:
            off = 0
            for d in colors_dtype.names:
                dt = colors_dtype[d]
                data = np.array(colors[off:off+dt.itemsize]).view(dt)[0]
                off += dt.itemsize
                f.colors[d] = data

        return f


class SemanticPoint(Enum):

    NONE = 0
    POSITION = 1
    POSITION_QUANTIZED = 2
    RGBA = 3
    RGB = 4
    RGB565 = 5
    NORMAL = 6
    NORMAL_OCT16P = 7
    BATCH_ID = 8


class FeatureTableHeader(object):

    def __init__(self):
        # point semantics
        self.positions = SemanticPoint.POSITION
        self.positions_offset = 0
        self.positions_dtype = None

        self.colors = SemanticPoint.NONE
        self.colors_offset = 0
        self.colors_dtype = None

        self.normal = SemanticPoint.NONE
        self.normal_offset = 0
        self.normal_dtype = None

        # global semantics
        self.points_length = 0
        self.rtc = None

    def to_array(self):
        jsond = self.to_json()
        json_str = json.dumps(jsond).replace(" ", "")
        n = len(json_str) + 28
        json_str += ' '*(4 - n % 4)
        return np.frombuffer(json_str.encode('utf-8'), dtype=np.uint8)

    def to_json(self):
        jsond = {}

        # length
        jsond['POINTS_LENGTH'] = self.points_length

        # rtc
        if self.rtc:
            jsond['RTC_CENTER'] = self.rtc

        # positions
        offset = {'byteOffset': self.positions_offset}
        if self.positions == SemanticPoint.POSITION:
            jsond['POSITION'] = offset
        elif self.positions == SemanticPoint.POSITION_QUANTIZED:
            jsond['POSITION_QUANTIZED'] = offset

        # colors
        offset = {'byteOffset': self.colors_offset}
        if self.colors == SemanticPoint.RGB:
            jsond['RGB'] = offset

        return jsond

    @staticmethod
    def from_dtype(positions_dtype, colors_dtype, npoints):
        """
        Parameters
        ----------
        positions_dtype : numpy.dtype
            Numpy description of a positions.

        colors_dtype : numpy.dtype
            Numpy description of a colors.

        Returns
        -------
        fth : FeatureTableHeader
        """

        fth = FeatureTableHeader()
        fth.points_length = npoints

        # search positions
        names = positions_dtype.names
        if ('X' in names) and ('Y' in names) and ('Z' in names):
            dtx = positions_dtype['X']
            dty = positions_dtype['Y']
            dtz = positions_dtype['Z']
            fth.positions_offset = 0
            if (dtx == np.float32 and dty == np.float32 and dtz == np.float32):
                fth.positions = SemanticPoint.POSITION
                fth.positions_dtype = np.dtype([('X', np.float32),
                                                ('Y', np.float32),
                                                ('Z', np.float32)])
            elif (dtx == np.uint16 and dty == np.uint16 and dtz == np.uint16):
                fth.positions = SemanticPoint.POSITION_QUANTIZED
                fth.positions_dtype = np.dtype([('X', np.uint16),
                                                ('Y', np.uint16),
                                                ('Z', np.uint16)])

        # search colors
        if colors_dtype is not None:
            names = colors_dtype.names
            if ('Red' in names) and ('Green' in names) and ('Blue' in names):
                if 'Alpha' in names:
                    fth.colors = SemanticPoint.RGBA
                    fth.colors_dtype = np.dtype([('Red', np.uint8),
                                                 ('Green', np.uint8),
                                                 ('Blue', np.uint8),
                                                 ('Alpha', np.uint8)])
                else:
                    fth.colors = SemanticPoint.RGB
                    fth.colors_dtype = np.dtype([('Red', np.uint8),
                                                 ('Green', np.uint8),
                                                 ('Blue', np.uint8)])

                fth.colors_offset = (fth.positions_offset
                                     + npoints*fth.positions_dtype.itemsize)
        else:
            fth.colors = SemanticPoint.NONE
            fth.colors_dtype = None

        return fth

    @staticmethod
    def from_array(array):
        """
        Parameters
        ----------
        array : numpy.array
            Json in 3D Tiles format. See py3dtiles/doc/semantics.json for an
            example.

        Returns
        -------
        fth : FeatureTableHeader
        """

        jsond = json.loads(array.tostring().decode('utf-8'))
        fth = FeatureTableHeader()

        # search position
        if "POSITION" in jsond:
            fth.positions = SemanticPoint.POSITION
            fth.positions_offset = jsond['POSITION']['byteOffset']
            fth.positions_dtype = np.dtype([('X', np.float32),
                                            ('Y', np.float32),
                                            ('Z', np.float32)])
        elif "POSITION_QUANTIZED" in jsond:
            fth.positions = SemanticPoint.POSITION_QUANTIZED
            fth.positions_offset = jsond['POSITION_QUANTIZED']['byteOffset']
            fth.positions_dtype = np.dtype([('X', np.uint16),
                                            ('Y', np.uint16),
                                            ('Z', np.uint16)])
        else:
            fth.positions = SemanticPoint.NONE
            fth.positions_offset = 0
            fth.positions_dtype = None

        # search colors
        if "RGB" in jsond:
            fth.colors = SemanticPoint.RGB
            fth.colors_offset = jsond['RGB']['byteOffset']
            fth.colors_dtype = np.dtype([('Red', np.uint8),
                                         ('Green', np.uint8),
                                         ('Blue', np.uint8)])
        else:
            fth.colors = SemanticPoint.NONE
            fth.colors_offset = 0
            fth.colors_dtype = None

        # points length
        if "POINTS_LENGTH" in jsond:
            fth.points_length = jsond["POINTS_LENGTH"]

        # RTC (Relative To Center)
        if "RTC_CENTER" in jsond:
            fth.rtc = jsond['RTC_CENTER']
        else:
            fth.rtc = None

        return fth


class FeatureTableBody(object):

    def __init__(self):
        self.positions_arr = []
        self.positions_itemsize = 0

        self.colors_arr = []
        self.colors_itemsize = 0

    def to_array(self):
        arr = self.positions_arr
        if len(self.colors_arr):
            arr = np.concatenate((self.positions_arr, self.colors_arr))
        return arr

    @staticmethod
    def from_features(fth, features):

        b = FeatureTableBody()

        # extract positions
        b.positions_itemsize = fth.positions_dtype.itemsize
        b.positions_arr = np.array([], dtype=np.uint8)

        if fth.colors_dtype is not None:
            b.colors_itemsize = fth.colors_dtype.itemsize
            b.colors_arr = np.array([], dtype=np.uint8)

        for f in features:
            fpos, fcol = f.to_array()
            b.positions_arr = np.concatenate((b.positions_arr, fpos))
            if fth.colors_dtype is not None:
                b.colors_arr = np.concatenate((b.colors_arr, fcol))

        return b

    @staticmethod
    def from_array(fth, array):
        """
        Parameters
        ----------
        header : FeatureTableHeader

        array : numpy.array

        Returns
        -------
        ftb : FeatureTableBody
        """

        b = FeatureTableBody()

        npoints = fth.points_length

        # extract positions
        pos_size = fth.positions_dtype.itemsize
        pos_offset = fth.positions_offset
        b.positions_arr = array[pos_offset:pos_offset+npoints*pos_size]
        b.positions_itemsize = pos_size

        # extract colors
        if fth.colors != SemanticPoint.NONE:
            col_size = fth.colors_dtype.itemsize
            col_offset = fth.colors_offset
            b.colors_arr = array[col_offset:col_offset+col_size*npoints]
            b.colors_itemsize = col_size

        return b

    def positions(self, n):
        itemsize = self.positions_itemsize
        return self.positions_arr[n*itemsize:(n+1)*itemsize]

    def colors(self, n):
        if len(self.colors_arr):
            itemsize = self.colors_itemsize
            return self.colors_arr[n*itemsize:(n+1)*itemsize]
        return []


class FeatureTable(object):

    def __init__(self):
        self.header = FeatureTableHeader()
        self.body = FeatureTableBody()

    def npoints(self):
        return self.header.points_length

    def to_array(self):
        fth_arr = self.header.to_array()
        ftb_arr = self.body.to_array()
        return np.concatenate((fth_arr, ftb_arr))

    @staticmethod
    def from_array(th, array):
        """
        Parameters
        ----------
        th : TileHeader

        array : numpy.array

        Returns
        -------
        ft : FeatureTable
        """

        # build feature table header
        fth_len = th.ft_json_byte_length
        fth_arr = array[0:fth_len]
        fth = FeatureTableHeader.from_array(fth_arr)

        # build feature table body
        ftb_len = th.ft_bin_byte_length
        ftb_arr = array[fth_len:fth_len+ftb_len]
        ftb = FeatureTableBody.from_array(fth, ftb_arr)

        # build feature table
        ft = FeatureTable()
        ft.header = fth
        ft.body = ftb

        return ft

    @staticmethod
    def from_features(pdtype, cdtype, features):
        """
        pdtype : numpy.dtype
            Numpy description for positions.

        cdtype : numpy.dtype
            Numpy description for colors.

        features : Feature[]

        Returns
        -------
        ft : FeatureTable
        """

        fth = FeatureTableHeader.from_dtype(pdtype, cdtype, len(features))
        ftb = FeatureTableBody.from_features(fth, features)

        ft = FeatureTable()
        ft.header = fth
        ft.body = ftb

        return ft

    def feature(self, n):
        pos = self.body.positions(n)
        col = self.body.colors(n)
        return Feature.from_array(self.header.positions_dtype, pos,
                                  self.header.colors_dtype, col)
