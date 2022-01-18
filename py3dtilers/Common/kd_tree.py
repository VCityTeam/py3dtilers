from .object_to_tile import ObjectsToTile


def kd_tree(objects, maxNumObjects, depth=0):
    """
    Distribute the geometries into ObjectsToTile.
    The objects are distributed by their centroid.
    :param objects: the geometries to distribute
    :param maxNumObjects: the max number of objects in each new group
    :param depth: the depth of the recursion

    :return: a list of ObjectsToTile
    """
    # objects should herited from objects_to_tile and
    # dispose of a method get_centroid()
    if (not isinstance(objects, ObjectsToTile)):
        return None

    derived = objects.__class__

    # The module argument of 2 (in the next line) hard-wires the fact that
    # this kd_tree is in fact a 2D_tree.
    axis = depth % 2

    # Within the sorting criteria point[1] refers to the centroid of the
    # bounding boxes of the city objects. And thus, depending on the value of
    # axis, we alternatively sort on the X or Y coordinate of those centroids:

    sObjects = derived(
        sorted(objects,
               key=lambda obj: obj.get_centroid()[axis]))
    median = len(sObjects) // 2
    lObjects = sObjects[:median]
    rObjects = sObjects[median:]
    pre_tiles = derived()
    if len(lObjects) > maxNumObjects:
        pre_tiles.extend(kd_tree(lObjects, maxNumObjects, depth + 1))
        pre_tiles.extend(kd_tree(rObjects, maxNumObjects, depth + 1))
    else:
        if len(lObjects) > 0:
            pre_tiles.append(lObjects)
        if len(rObjects) > 0:
            pre_tiles.append(rObjects)
    return pre_tiles
