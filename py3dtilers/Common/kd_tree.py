from .feature import FeatureList


def kd_tree(feature_list, maxNumObjects, depth=0):
    """
    Distribute the features into FeatureList.
    The objects are distributed by their centroid.
    :param objects: the features to distribute
    :param maxNumObjects: the max number of objects in each new group
    :param depth: the depth of the recursion

    :return: a list of FeatureList
    """
    # objects should herited from feature_list and
    # dispose of a method get_centroid()
    if (not isinstance(feature_list, FeatureList)):
        return None

    derived = feature_list.__class__

    # The module argument of 2 (in the next line) hard-wires the fact that
    # this kd_tree is in fact a 2D_tree.
    axis = depth % 2

    # Within the sorting criteria point[1] refers to the centroid of the
    # bounding boxes of the city objects. And thus, depending on the value of
    # axis, we alternatively sort on the X or Y coordinate of those centroids:

    feature_list.set_features(sorted(feature_list, key=lambda obj: obj.get_centroid()[axis]))
    median = len(feature_list) // 2
    lObjects = feature_list[:median]
    rObjects = feature_list[median:]
    pre_tiles = derived()
    if len(lObjects) > maxNumObjects or len(rObjects) > maxNumObjects:
        pre_tiles.extend(kd_tree(lObjects, maxNumObjects, depth + 1))
        pre_tiles.extend(kd_tree(rObjects, maxNumObjects, depth + 1))
    else:
        if len(lObjects) > 0:
            pre_tiles.append(lObjects)
        if len(rObjects) > 0:
            pre_tiles.append(rObjects)
    return pre_tiles
