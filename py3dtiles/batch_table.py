# -*- coding: utf-8 -*-

import sys
import numpy as np
import json
from .threedtiles_notion import ThreeDTilesNotion

class BatchTable(ThreeDTilesNotion):
    """
    Only the JSON header has been implemented for now. According to the batch
    table documentation, the binary body is useful for storing long arrays of
    data (better performances)
    """

    def __init__(self):
        super().__init__()

    def to_array(self):
        """
        Returns the batch table represented as a binary
        """
        # convert dict to json string
        bt_json = json.dumps(self.header, separators=(',', ':'))
        # header must be 4-byte aligned (refer to batch table documentation)
        bt_json += ' '*(4 - len(bt_json) % 4)
        # returns an array of binaries representing the batch table
        return np.fromstring(bt_json, dtype=np.uint8)
