# -*- coding: utf-8 -*-
import sys
from py3dtiles import ThreeDTilesNotion

class BoundingVolume(ThreeDTilesNotion):

    def __init__(self):
        super().__init__()
        # Because this is oneOf the following, implementation is simpler
        # without defining the following entries:
        # self.header["box"]
        # self.header["region"]
        # self.header["sphere"]

    def set(self, volume_type, array):
        if not (volume_type == "box"    or
                volume_type == "region" or
                volume_type == "sphere"):
            print(f'Erroneous volume type {volume_type}')
            sys.exit(1)
        self.add_property_from_array(volume_type, array)

    def is_box(self):
        return 'box' in self.header

    def set_box(self, box):
        if "region" in self.header:
            print('Warning: overwriting existing region with a box.')
            del self.header["region"]
        if "sphere" in self.header:
            print('Warning: overwriting existing sphere with a box.')
            del self.header["sphere"]
        if "box" in self.header:
            print('Warning: overwriting existing box with a new one.')
        self.header["box"] = box

    def get_box(self):
        if not self.is_box():
            print('Requiring the box of a non box bounding volume')
            sys.exit(1)
        return self.header["box"]

    def prepare_for_json(self):
        defined = 0
        if "box" in self.header:
            defined += 1
            if not self.header["box"].is_valid():
                sys.exit(1)
        if "region" in self.header:
            defined += 1
            if not len(self.header["region"]) == 6:
                print("A region BoundingVolume must have eactly 6 items.")
                sys.exit(1)
        if "sphere" in self.header:
            defined += 1
            if not len(self.header["sphere"]) == 4:
                print("A sphere BoundingVolume must have eactly 4 items.")
                sys.exit(1)
        if not defined == 1:
            print("BoundingVolumes must have a box, a region or a sphere")
            sys.exit(1)