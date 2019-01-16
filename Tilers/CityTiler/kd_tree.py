from building import Buildings


def kd_tree(buildings, maxNumBuildings, depth=0):
    # The module argument of 2 (in the next line) hard-wires the fact that
    # this kd_tree is in fact a 2D_tree.
    axis = depth % 2

    # Within the sorting criteria point[1] refers to the centroid of the
    # bounding boxes of the buildings. And thus, depending on the value of
    # axis, we alternatively sort on the X or Y coordinate of those centroids:
    sBuildings = Buildings(
                    sorted(buildings,
                    key=lambda building: building.getCentroid()[axis]))
    median = len(sBuildings) // 2
    lBuildings = sBuildings[:median]
    rBuildings = sBuildings[median:]
    pre_tiles = Buildings()
    if len(lBuildings) > maxNumBuildings:
        pre_tiles.extend(kd_tree(lBuildings, maxNumBuildings, depth + 1))
        pre_tiles.extend(kd_tree(rBuildings, maxNumBuildings, depth + 1))
    else:
        pre_tiles.append(lBuildings)
        pre_tiles.append(rBuildings)
    return pre_tiles