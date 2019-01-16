from py3dtiles import BoundingVolumeBox


class Building(object):

    def __init__(self, id, box_in):
        """
        :param id: given identifier
        :param box_2D: the maximum extents of the geometry a returned by a
                       PostGis::Box3D(geometry geomA) call (refer to
                       https://postgis.net/docs/Box3D.html) that is a string
                       of the form 'BOX3D(1 2 3, 4 5 6)' where:
                        * 1, 2 and 3 are the respective minimum of X, Y and Z
                        * 4, 5 and 6 are the respective maximum of X, Y and Z
        """
        self.id = id
        # 'BOX3D(1 2 3, 4 5 6)' -> [[1, 2, 3], [4, 5, 6]]
        box_parsed = [[float(coord) for coord in point.split(' ')]
                                    for point in box_in[6:-1].split(',')]
        x_min = box_parsed[0][0]
        x_max = box_parsed[1][0]
        y_min = box_parsed[0][1]
        y_max = box_parsed[1][1]
        z_min = box_parsed[0][2]
        z_max = box_parsed[1][2]

        self.box = BoundingVolumeBox()
        self.box.set_from_mins_maxs([x_min, y_min, z_min, x_max, y_max, z_max])
        # Centroid of the box
        self.centroid = [(x_min + x_max) / 2.0,
                         (y_min + y_max) / 2.0,
                         (z_min + z_max) / 2.0]

    def getId(self):
        return self.id

    def getCentroid(self):
        return self.centroid

    def getBoundingVolumeBox(self):
        return self.box


class Buildings:
    """
    A decorated list of Buildings.
    """
    def __init__(self, buildings=None):
        self.buildings = list()
        if buildings:
            self.buildings.extend(buildings)

    def __iter__(self):
        return iter(self.buildings)

    def __getitem__(self, item):
        return Buildings(self.buildings.__getitem__(item))

    def append(self, building):
        self.buildings.append(building)

    def extend(self, others):
        self.buildings.extend(others)

    def __len__(self):
        return len(self.buildings)

    def getCentroid(self):
        centroid = [0., 0., 0.]
        for building in self:
            centroid[0] += building.getCentroid()[0]
            centroid[1] += building.getCentroid()[1]
            centroid[2] += building.getCentroid()[2]
        return [centroid[0] / len(self),
                centroid[1] / len(self),
                centroid[2] / len(self)]