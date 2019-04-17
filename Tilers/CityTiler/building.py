from py3dtiles import BoundingVolumeBox


class Building(object):

    def __init__(self, database_id=None, box_in=None):
        """
        :param id: given identifier
        :param box_2D: the maximum extents of the geometry a returned by a
                       PostGis::Box3D(geometry geomA) call (refer to
                       https://postgis.net/docs/Box3D.html) that is a string
                       of the form 'BOX3D(1 2 3, 4 5 6)' where:
                        * 1, 2 and 3 are the respective minimum of X, Y and Z
                        * 4, 5 and 6 are the respective maximum of X, Y and Z
        """

        # The identifier of the database
        self.database_id = None

        # The City GML identifier (out of the "original" CityGML data file)
        self.gml_id = None

        # A Bounding Volume Box object
        self.box = None

        # The centroid of the box
        self.centroid = None

        if database_id:
            self.set_database_id(database_id)
        if box_in:
            self.set_box(box_in)

    def set_box(self, box_in):
        # Realize the following convertion:
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

    def set_database_id(self, id):
        self.database_id = id

    def get_database_id(self):
        return self.database_id

    def set_gml_id(self, gml_id):
        self.gml_id = gml_id

    def get_gml_id(self):
        return self.gml_id

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
        if isinstance(item, slice):
            return Buildings(self.buildings.__getitem__(item))
        # item is then an int type:
        return self.buildings.__getitem__(item)

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