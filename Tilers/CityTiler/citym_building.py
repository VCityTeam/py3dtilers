# -*- coding: utf-8 -*-
from citym_cityobject import CityMCityObject, CityMCityObjects


class CityMBuilding(CityMCityObject):
    def __init__(self):
        super().__init__()


class CityMBuildings(CityMCityObjects):
    with_bth = False

    def __init__(self):
        super().__init__()

    @staticmethod
    def set_bth():
        CityMBuildings.with_bth = True

    @staticmethod
    def is_bth_set():
        return CityMBuildings.with_bth
