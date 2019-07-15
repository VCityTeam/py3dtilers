from cityobject import CityObjects


def kd_tree(cityobjects, maxNumCityObjects, depth=0):
    # The module argument of 2 (in the next line) hard-wires the fact that
    # this kd_tree is in fact a 2D_tree.
    axis = depth % 2

    # Within the sorting criteria point[1] refers to the centroid of the
    # bounding boxes of the city objects. And thus, depending on the value of
    # axis, we alternatively sort on the X or Y coordinate of those centroids:
    sCityObjects = CityObjects(
                    sorted(cityobjects,
                    key=lambda building: building.getCentroid()[axis]))
    median = len(sCityObjects) // 2
    lCityObjects = sCityObjects[:median]
    rCityObjects = sCityObjects[median:]
    pre_tiles = CityObjects()
    if len(lCityObjects) > maxNumCityObjects:
        pre_tiles.extend(kd_tree(lCityObjects, maxNumCityObjects, depth + 1))
        pre_tiles.extend(kd_tree(rCityObjects, maxNumCityObjects, depth + 1))
    else:
        pre_tiles.append(lCityObjects)
        pre_tiles.append(rCityObjects)
    return pre_tiles