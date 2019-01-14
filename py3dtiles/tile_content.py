# -*- coding: utf-8 -*-

import numpy as np
from enum import Enum
from abc import ABC, abstractmethod
from .threedtiles_notion import ThreeDTilesNotion

class TileContent(ABC, ThreeDTilesNotion):

    def __init__(self):
        super().__init__()
        self.header = None
        self.body = None
        self.attributes["uri"] = "Dummy content set by TileContent:__init__()"

    def to_array(self):
        self.sync()
        header_arr = self.header.to_array()
        body_arr = self.body.to_array()
        return np.concatenate((header_arr, body_arr))

    def to_hex_str(self):
        arr = self.to_array()
        return " ".join("{:02X}".format(x) for x in arr)

    def save_as(self, filename):
        tile_arr = self.to_array()
        with open(filename, 'bw') as f:
            f.write(bytes(tile_arr))

    def sync(self):
        """
        Allow to synchronize headers with contents.
        """
        self.header.sync(self.body)

    def set_uri(self, uri):
        self.attributes["uri"] = uri

    def get_uri(self):
        return self.attributes["uri"]

class TileContentType(Enum):

    UNKNWON = 0
    POINTCLOUD = 1
    BATCHED3DMODEL = 2


class TileContentHeader(ABC):
    @abstractmethod
    def from_array(self, array):
        pass

    @abstractmethod
    def to_array(self):
        pass

    @abstractmethod
    def sync(self, body):
        pass


class TileContentBody(object):
    @abstractmethod
    def to_array(self):
        pass
