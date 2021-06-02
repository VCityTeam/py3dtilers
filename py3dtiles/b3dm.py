# -*- coding: utf-8 -*-
import struct
import numpy as np

from .tile_content import TileContent, TileContentHeader, TileContentBody
from .tile_content import TileContentType
from .gltf import GlTF
from .batch_table import BatchTable


class B3dm(TileContent):

    @staticmethod
    def from_glTF(gltf, bt=None):
        """
        Parameters
        ----------
        gltf : GlTF
            glTF object representing a set of objects

        bt : Batch Table (optional)
            BatchTable object containing per-feature metadata

        Returns
        -------
        tile : TileContent
        """

        tb = B3dmBody()
        tb.glTF = gltf
        tb.batch_table = bt

        th = B3dmHeader()
        th.sync(tb)

        t = TileContent()
        t.body = tb
        t.header = th

        return t

    @staticmethod
    def from_array(array):
        """
        Parameters
        ----------
        array : numpy.array

        Returns
        -------
        t : TileContent
        """

        # build TileContent header
        h_arr = array[0:B3dmHeader.BYTELENGTH]
        h = B3dmHeader.from_array(h_arr)

        if h.tile_byte_length != len(array):
            raise RuntimeError("Invalid byte length in header")

        # build TileContent body
        b_arr = (array[B3dmHeader.BYTELENGTH:h.tile_byte_length
                 - B3dmHeader.BYTELENGTH])
        b = B3dmBody.from_array(h, b_arr)

        # build TileContent with header and body
        t = TileContent()
        t.header = h
        t.body = b

        return t


class B3dmHeader(TileContentHeader):
    BYTELENGTH = 28

    def __init__(self):
        self.type = TileContentType.BATCHED3DMODEL
        self.magic_value = b"b3dm"
        self.version = 1
        self.tile_byte_length = 0
        self.ft_json_byte_length = 0
        self.ft_bin_byte_length = 0
        self.bt_json_byte_length = 0
        self.bt_bin_byte_length = 0
        self.bt_length = 0  # number of models in the batch

    def to_array(self):
        header_arr = np.frombuffer(self.magic_value, np.uint8)

        header_arr2 = np.array([self.version,
                                self.tile_byte_length,
                                self.ft_json_byte_length,
                                self.ft_bin_byte_length,
                                self.bt_json_byte_length,
                                self.bt_bin_byte_length], dtype=np.uint32)

        return np.concatenate((header_arr, header_arr2.view(np.uint8)))

    def sync(self, body):
        """
        Allow to synchronize headers with contents.
        """

        # extract array
        glTF_arr = body.glTF.to_array()

        # sync the TileContent header with feature table contents
        self.tile_byte_length = len(glTF_arr) + B3dmHeader.BYTELENGTH
        self.bt_json_byte_length = 0
        self.bt_bin_byte_length = 0
        self.ft_json_byte_length = 0
        self.ft_bin_byte_length = 0

        if body.batch_table is not None:
            bth_arr = body.batch_table.to_array()
            # btb_arr = body.batch_table.body.to_array()

            self.tile_byte_length += len(bth_arr)
            self.bt_json_byte_length = len(bth_arr)

        # fth_arr = body.feature_table.header.to_array()
        # ftb_arr = body.feature_table.body.to_array()

    @staticmethod
    def from_array(array):
        """
        Parameters
        ----------
        array : numpy.array

        Returns
        -------
        h : TileContentHeader
        """

        h = B3dmHeader()

        if len(array) != B3dmHeader.BYTELENGTH:
            raise RuntimeError("Invalid header length")

        h.magic_value = "b3dm"
        h.version = struct.unpack("i", array[4:8])[0]
        h.tile_byte_length = struct.unpack("i", array[8:12])[0]
        h.ft_json_byte_length = struct.unpack("i", array[12:16])[0]
        h.ft_bin_byte_length = struct.unpack("i", array[16:20])[0]
        h.bt_json_byte_length = struct.unpack("i", array[20:24])[0]
        h.bt_bin_byte_length = struct.unpack("i", array[24:28])[0]

        h.type = TileContentType.BATCHED3DMODEL

        return h


class B3dmBody(TileContentBody):
    def __init__(self):
        self.batch_table = BatchTable()
        # self.feature_table = FeatureTable()
        self.glTF = GlTF()

    def to_array(self):
        # TODO : export feature table
        array = self.glTF.to_array()
        if self.batch_table is not None:
            array = np.concatenate((self.batch_table.to_array(), array))
        return array

    @staticmethod
    def from_glTF(glTF):
        """
        Parameters
        ----------
        glTF : GlTF

        Returns
        -------
        b : TileContentBody
        """

        # build TileContent body
        b = B3dmBody()
        b.glTF = glTF

        return b

    @staticmethod
    def from_array(th, array):
        """
        Parameters
        ----------
        th : TileContentHeader

        array : numpy.array

        Returns
        -------
        b : TileContentBody
        """

        # build feature table
        ft_len = th.ft_json_byte_length + th.ft_bin_byte_length
        # ft_arr = array[0:ft_len]
        # ft = FeatureTable.from_array(th, ft_arr)

        # build batch table
        bt_len = th.bt_json_byte_length + th.bt_bin_byte_length
        # bt_arr = array[ft_len:ft_len+bt_len]
        # bt = BatchTable.from_array(th, bt_arr)

        # build glTF
        glTF_len = (th.tile_byte_length - ft_len - bt_len
                    - B3dmHeader.BYTELENGTH)
        glTF_arr = array[ft_len+bt_len:ft_len+bt_len+glTF_len]
        glTF = GlTF.from_array(glTF_arr)

        # build TileContent body with feature table
        b = B3dmBody()
        # b.feature_table = ft
        # b.batch_table = bt
        b.glTF = glTF

        return b
