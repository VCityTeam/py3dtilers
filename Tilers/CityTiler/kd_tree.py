from citym_cityobject import CityMCityObjects


def kd_tree(cityobjects, maxNumCityMCityObjects, depth=0):
    # The module argument of 2 (in the next line) hard-wires the fact that
    # this kd_tree is in fact a 2D_tree.
    axis = depth % 2

    # Within the sorting criteria point[1] refers to the centroid of the
    # bounding boxes of the city objects. And thus, depending on the value of
    # axis, we alternatively sort on the X or Y coordinate of those centroids:
    sCityMCityObjects = CityMCityObjects(
                    sorted(cityobjects,
                    key=lambda building: building.get_centroid()[axis]))
    median = len(sCityMCityObjects) // 2
    lCityMCityObjects = sCityMCityObjects[:median]
    rCityMCityObjects = sCityMCityObjects[median:]
    pre_tiles = CityMCityObjects()
    if len(lCityMCityObjects) > maxNumCityMCityObjects:
        pre_tiles.extend(kd_tree(lCityMCityObjects, maxNumCityMCityObjects, depth + 1))
        pre_tiles.extend(kd_tree(rCityMCityObjects, maxNumCityMCityObjects, depth + 1))
    else:
        pre_tiles.append(lCityMCityObjects)
        pre_tiles.append(rCityMCityObjects)
    return pre_tiles