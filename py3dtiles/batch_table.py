# -*- coding: utf-8 -*-

from .threedtiles_notion import ThreeDTilesNotion


class BatchTable(ThreeDTilesNotion):
    """
    Only the JSON header has been implemented for now. According to the batch
    table documentation, the binary body is useful for storing long arrays of
    data (better performances)
    """

    def __init__(self):
        super().__init__()