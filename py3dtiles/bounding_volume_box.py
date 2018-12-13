# -*- coding: utf-8 -*-
import sys
import numpy
from .threedtiles_notion import ThreeDTilesNotion
from .bounding_volume import BoundingVolume

# In order to prevent the appearance of ghost newline characters ("\n")
# when printing a numpy.array (mainly self.header['box'] in this file):
numpy.set_printoptions(linewidth=200)

class BoundingVolumeBox(ThreeDTilesNotion, BoundingVolume):
    """
    A box bounding volume as defined in the 3DTiles specifications i.e. an
    array of 12 numbers that define an oriented bounding box:
    - The first three elements define the x, y, and z values for the
      center of the box.
    - The next three elements (with indices 3, 4, and 5) define the x axis
      direction and half-length.
    - The next three elements (with indices 6, 7, and 8) define the y axis
      direction and half-length.
    - The last three elements (indices 9, 10, and 11) define the z axis
      direction and half-length."
    Note that, by default, a box bounding volume doesn't need to be aligned
    with the coordinate axis. Still in general, computing the box bounding
    volume of two box bounding volumes won't necessarily yield a box that is
    aligned with the coordinate axis (although this computation might require
    some fitting algorithm e.g. the principal component analysis method.
    Yet in sake of simplification (and numerical efficiency), when asked to
    "add" (i.e. to find the enclosing box of) two (or more) box bounding
    volumes this class resolves to compute the "canonical" fitting/enclosing
    box i.e. a box that is parallel to the coordinate axis.
    """
    def __init__(self):
        super().__init__()
        self.header['box'] = None

    def is_box(self):
        return True

    def set_from_list(self, array):
        self.header["box"] = numpy.array([float(i) for i in array],
                                         dtype=numpy.float)

    def get_corners(self):
        """
        :return: the corners of box as a list
        """
        if not self.is_valid():
            sys.exit(1)

        center      = self.header["box"][0: 3: 1]
        x_half_axis = self.header["box"][3: 6: 1]
        y_half_axis = self.header["box"][6: 9: 1]
        z_half_axis = self.header["box"][9:12: 1]

        x_axis = x_half_axis * 2
        y_axis = y_half_axis * 2
        z_axis = z_half_axis * 2

        # The eight cornering points of the box
        tmp   = numpy.subtract(center,x_half_axis)
        tmp   = numpy.subtract(tmp,   y_half_axis)

        o     = numpy.subtract(tmp,   z_half_axis)
        ox    = numpy.add(o, x_axis)
        oy    = numpy.add(o, y_axis)
        oxy   = numpy.add(o, numpy.add(x_axis, y_axis))

        oz    = numpy.add(o, z_axis)
        oxz   = numpy.add(oz, x_axis)
        oyz   = numpy.add(oz, y_axis)
        oxyz  = numpy.add(oz, numpy.add(x_axis, y_axis))

        return [o, ox, oy, oxy, oz, oxz, oyz, oxyz]

    def get_canonical(self):
        """
        :return: the smallest enclosing box that is parallel to the
                 coordinate axis
        """
        corners = self.get_corners()
        x_min = min( c[0] for c in corners)
        x_max = max( c[0] for c in corners)
        y_min = min( c[1] for c in corners)
        y_max = max( c[1] for c in corners)
        z_min = min( c[2] for c in corners)
        z_max = max( c[2] for c in corners)

        new_center = numpy.array([(x_min + x_max) / 2,
                               (y_min + y_max) / 2,
                               (z_min + z_max) / 2])
        new_x_half_axis = numpy.array([(x_max - x_min) / 2, 0, 0])
        new_y_half_axis = numpy.array([0, (y_max - y_min) / 2, 0])
        new_z_half_axis = numpy.array([0, 0, (z_max - z_min) / 2])

        return numpy.concatenate((new_center,
                                  new_x_half_axis,
                                  new_y_half_axis,
                                  new_z_half_axis))

    def add(self, other):
        """
        Compute the 'canonical' bounding volume fitting this bounding volume
        together with the added bounding volume. Again (refer above to the
        class definition) the computed fitting bounding volume is generically
        not the smallest one (due to its alignment with the coordinate axis).
        :param other: another box bounding volume to be added with this one
        """
        if not self.is_defined():
            # Then it is safe to overwrite
            self.header["box"] = other.header["box"]
            return

        corners = self.get_corners() + other.get_corners()
        x_min = min( c[0] for c in corners)
        x_max = max( c[0] for c in corners)
        y_min = min( c[1] for c in corners)
        y_max = max( c[1] for c in corners)
        z_min = min( c[2] for c in corners)
        z_max = max( c[2] for c in corners)

        new_center = numpy.array([(x_min + x_max) / 2,
                                  (y_min + y_max) / 2,
                                  (z_min + z_max) / 2])
        new_x_half_axis = numpy.array([(x_max - x_min) / 2, 0, 0])
        new_y_half_axis = numpy.array([0, (y_max - y_min) / 2, 0])
        new_z_half_axis = numpy.array([0, 0, (z_max - z_min) / 2])

        result = BoundingVolumeBox()
        result.array = numpy.concatenate((new_center,
                                          new_x_half_axis,
                                          new_y_half_axis,
                                          new_z_half_axis))
        return result

    def is_defined(self):
        if 'box' not in self.header:
            return False
        if not isinstance(self.header['box'], numpy.ndarray):
            return False
        return True

    def is_valid(self):
        if not self.is_defined():
            print('Warning: Bounding Volume Box is not defined.')
            return False
        if not self.header['box'].ndim == 1:
            print('Warning: Bounding Volume Box has wrong dimensions.')
            return False
        if not self.header['box'].shape[0] == 12:
            print('Warning: Bounding Volume Box must have 12 elements.')
            return False
        return True

    def prepare_for_json(self):
        if not self.is_valid():
            print('Warning: invalid Bounding Volume Box cannot be prepared.')
            sys.exit(1)


if __name__ == '__main__':
    box = BoundingVolumeBox()

    # Getting canonical first example
    box.set_from_list([2,3,4,  2,0,0,  0,3,0,  0,0,4])
    print("This aligned box and its canonical one should be identical:")
    print("         original: ", box.header['box'])
    print("        canonical: ", box.get_canonical())

    # Getting canonical second example
    box.set_from_list([0,0,0,  1,1,0,  -1,1,0,  0,0,1])
    print("But when considering a rotated cube of size 2, the canonical",
          "fitting box is different:")
    print("         original: ", box.header['box'])
    print("        canonical: ", box.get_canonical())

    # Adding volumes
    box.set_from_list([1,1,1,  1,0,0,  0,1,0,  0,0,1])
    other = BoundingVolumeBox()
    other.set_from_list([9,9,9,  1,0,0,  0,1,0,  0,0,1])
    print("Consider the two following box bounding volumes:")
    print("    first: ", box.header['box'])
    print("   second: ", other.header['box'])

    fitting_volume = box.add(other)
    print("When added we get the cube centered at (5,5,5) and with a 5 size:")
    print("   addition result: ", fitting_volume.box)