import numpy as np
from shapely.geometry import LineString


class LineBuffer():
    """
    A LineBuffer allows to create a polygon from a line by applying a buffer on this line.
    The buffer size depends on the offset of the LineBuffer instance.
    """

    def __init__(self, buffer_size=1):
        self.offset = buffer_size / 2

    def line_intersect(self, l1_start, l1_end, l2_start, l2_end):
        """
        https://stackoverflow.com/questions/64463369/intersection-of-two-infinite-lines-specified-by-points
        Find the intersection between 2 lines, each line is defined by 2 points
        """
        p1_start = np.asarray(l1_start)
        p1_end = np.asarray(l1_end)
        p2_start = np.asarray(l2_start)
        p2_end = np.asarray(l2_end)

        p = p1_start
        r = (p1_end - p1_start)
        q = p2_start
        s = (p2_end - p2_start)

        t = np.cross(q - p, s) / (np.cross(r, s))
        i = p + t * r
        return i.tolist()

    def get_parallel_offset(self, start_point, end_point, offset=3):
        """
        Return the parallel offsets (left and right) of a line
        :param start_point: the starting point of the line
        :param end_point: the ending point of the line
        :param offset: the distance between the line and its parallel offsets

        :return: left and right parallel offsets a list of points
        """
        line = LineString([start_point, end_point])
        po_left = list(line.parallel_offset(offset, 'left', join_style=2, resolution=1).coords)
        po_right = list(line.parallel_offset(offset, 'right', join_style=2, resolution=1).coords)
        return po_left, po_right

    def buffer_line_string(self, coordinates):
        """
        Take a line string as coordinates
        :param coordinates: a list of 3D points ([x, y, z])

        :return: a buffered polygon
        """
        polygon = [None] * (len(coordinates) * 2)
        width_offset = self.offset

        po_1_left, po_1_right = self.get_parallel_offset(coordinates[0], coordinates[1], offset=width_offset)
        polygon[0] = [po_1_left[0][0], po_1_left[0][1], coordinates[0][2]]
        polygon[(len(coordinates) * 2) - 1] = [po_1_right[0][0], po_1_right[0][1], coordinates[0][2]]

        po_2_left, po_2_right = self.get_parallel_offset(coordinates[len(coordinates) - 2], coordinates[len(coordinates) - 1], offset=width_offset)
        polygon[len(coordinates) - 1] = [po_2_left[1][0], po_2_left[1][1], coordinates[len(coordinates) - 1][2]]
        polygon[len(coordinates)] = [po_2_right[1][0], po_2_right[1][1], coordinates[len(coordinates) - 1][2]]

        for i in range(0, len(coordinates) - 2):
            po_1_left, po_1_right = self.get_parallel_offset(coordinates[i], coordinates[i + 1], offset=width_offset)
            po_2_left, po_2_right = self.get_parallel_offset(coordinates[i + 1], coordinates[i + 2], offset=width_offset)

            intersection_left = self.line_intersect(po_1_left[0], po_1_left[1], po_2_left[0], po_2_left[1])
            intersection_right = self.line_intersect(po_1_right[0], po_1_right[1], po_2_right[0], po_2_right[1])
            polygon[i + 1] = [intersection_left[0], intersection_left[1], coordinates[i + 1][2]]
            polygon[len(polygon) - 2 - i] = [intersection_right[0], intersection_right[1], coordinates[i + 1][2]]

        return [coord for coord in polygon if not np.isnan(np.sum(coord))]
