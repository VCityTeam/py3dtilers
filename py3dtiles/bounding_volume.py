# -*- coding: utf-8 -*-
import sys
from .threedtiles_notion import ThreeDTilesNotion


class BoundingVolume:
    """
    Abstract class used as interface for box, region and sphere
    """
    # def __init__(self):

    def is_box(self):
        return False

    def is_region(self):
        return False

    def is_sphere(self):
        return False