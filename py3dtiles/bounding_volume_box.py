# -*- coding: utf-8 -*-
import sys
import numpy
import copy
from .threedtiles_notion import ThreeDTilesNotion
from .bounding_volume import BoundingVolume

# In order to prevent the appearance of ghost newline characters ("\n")
# when printing a numpy.array (mainly self.attributes['box'] in this file):
numpy.set_printoptions(linewidth=500)


class BoundingVolumeBox(ThreeDTilesNotion, BoundingVolume, object):
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
        self.attributes['box'] = None

    def get_center(self):
        return self.attributes["box"][0: 3: 1]

    def translate(self, offset):
        """
        Translate the box center with the given offset "vector"
        :param offset: the 3D vector by which the box should be translated
        """
        for i in range(0,3):
            self.attributes["box"][i] += offset[i]

    def transform(self, transform):
        """
        Apply the provided transformation matrix (4x4) to the box
        :param transform: transformation matrix (4x4) to be applied
        """
        # FIXME: the following code only uses the first three coordinates
        # of the transformation matrix (and basically ignores the fourth
        # column of transform). This looks like some kind of mistake...
        rotation = numpy.array([ transform[0:3],
                                 transform[4:7],
                                 transform[8:11]])

        center      = self.attributes["box"][0: 3: 1]
        x_half_axis = self.attributes["box"][3: 6: 1]
        y_half_axis = self.attributes["box"][6: 9: 1]
        z_half_axis = self.attributes["box"][9:12: 1]

        # Apply the rotation part to each element
        new_center = rotation.dot(center)
        new_x_half_axis = rotation.dot(x_half_axis)
        new_y_half_axis = rotation.dot(y_half_axis)
        new_z_half_axis = rotation.dot(z_half_axis)
        self.attributes["box"] = numpy.concatenate((new_center,
                                                    new_x_half_axis,
                                                    new_y_half_axis,
                                                    new_z_half_axis))
        offset = numpy.array(transform[12:15])
        self.translate(offset)

    @staticmethod
    def get_box_array_from_point(points):
        """
        :param points: a list of 3D points
        :return: the smallest box (as an array, as opposed to a
                BoundingVolumeBox instance) that encloses the given list of
                (3D) points and that is parallel to the coordinate axis.
        """
        return BoundingVolumeBox.get_box_array_from_mins_maxs(
            [ min(c[0] for c in points),
              min(c[1] for c in points),
              min(c[2] for c in points),
              max(c[0] for c in points),
              max(c[1] for c in points),
              max(c[2] for c in points) ])

    @staticmethod
    def get_box_array_from_mins_maxs(mins_maxs):
        """
        :param mins_maxs: the list [x_min, y_min, z_min, x_max, y_max, z_max]
                          that is the boundaries of the box along each
                          coordinate axis
        :return: the smallest box (as an array, as opposed to a
                BoundingVolumeBox instance) that encloses the given list of
                (3D) points and that is parallel to the coordinate axis.
        """
        x_min = mins_maxs[0]
        x_max = mins_maxs[3]
        y_min = mins_maxs[1]
        y_max = mins_maxs[4]
        z_min = mins_maxs[2]
        z_max = mins_maxs[5]

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

    def is_box(self):
        return True

    def set_from_list(self, box_list):
        self.attributes["box"] = numpy.array([float(i) for i in box_list],
                                             dtype=numpy.float)

    def set_from_array(self, box_array):
        self.attributes["box"] = box_array

    def set_from_points(self, points):
        self.attributes["box"] = \
                            BoundingVolumeBox.get_box_array_from_point(points)

    def set_from_mins_maxs(self, mins_maxs):
        """
        :param mins_maxs: the list [x_min, y_min, z_min, x_max, y_max, z_max]
                          that is the boundaries of the box along each
                          coordinate axis
        """
        self.attributes["box"] = \
            BoundingVolumeBox.get_box_array_from_mins_maxs(mins_maxs)

    def get_corners(self):
        """
        :return: the corners (3D points) of the box as a list
        """
        if not self.is_valid():
            sys.exit(1)

        center      = self.attributes["box"][0: 3: 1]
        x_half_axis = self.attributes["box"][3: 6: 1]
        y_half_axis = self.attributes["box"][6: 9: 1]
        z_half_axis = self.attributes["box"][9:12: 1]

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

    def get_canonical_as_array(self):
        """
        :return: the smallest enclosing box (as an array) that is parallel
                 to the coordinate axis
        """
        return BoundingVolumeBox.get_box_array_from_point(self.get_corners())

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
            self.attributes["box"] = other.attributes["box"]
            return

        corners = self.get_corners() + other.get_corners()
        self.set_from_points(corners)

    def is_defined(self):
        if 'box' not in self.attributes:
            return False
        if not isinstance(self.attributes['box'], numpy.ndarray):
            return False
        return True

    def is_valid(self):
        if not self.is_defined():
            print('Warning: Bounding Volume Box is not defined.')
            return False
        if not self.attributes['box'].ndim == 1:
            print('Warning: Bounding Volume Box has wrong dimensions.')
            return False
        if not self.attributes['box'].shape[0] == 12:
            print('Warning: Bounding Volume Box must have 12 elements.')
            return False
        return True

    def prepare_for_json(self):
        if not self.is_valid():
            print('Warning: invalid Bounding Volume Box cannot be prepared.')
            sys.exit(1)

    @classmethod
    def get_children(cls, owner):
        children_bv = list()
        for child in owner.get_children():
            bounding_volume = child.get_bounding_volume()
            if not bounding_volume:
                print(f'This child {child} has no bounding volume.')
                print('Exiting')
                sys.exit(1)
            children_bv.append(bounding_volume)
        return children_bv

    def sync_with_children(self, owner):
        if not owner.has_children():
            # We consider that whatever information is present it is the
            # proper one (in other terms: when no sub-boxes are present
            # then the owner is leaf tile and we have nothing to update)
            return
        # We reset to some dummy state of this Bounding Volume Box so we
        # can add up in place the boxes of the owner's children
        self.set_from_list([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        print("Warning: overwriting box bounding volume.")
        for child in owner.get_children():
            # FIXME have the transform method return a new object and
            # define another method to apply_transform in place
            bounding_volume = copy.deepcopy(child.get_bounding_volume())
            bounding_volume.transform(child.get_transform())
            if not bounding_volume.is_box():
                print('Dropping child with non box bounding volume.')
                continue
            self.add(bounding_volume)
        self.sync_extensions(owner)


if __name__ == '__main__':
    box = BoundingVolumeBox()

    # Getting canonical first example
    box.set_from_list([2,3,4,  2,0,0,  0,3,0,  0,0,4])
    print("This aligned box and its canonical one should be identical:")
    print("         original: ", box.attributes['box'])
    print("        canonical: ", box.get_canonical_as_array())

    # Getting canonical second example
    box.set_from_list([0,0,0,  1,1,0,  -1,1,0,  0,0,1])
    print("But when considering a rotated cube of size 2, the canonical",
          "fitting box is different:")
    print("         original: ", box.attributes['box'])
    print("        canonical: ", box.get_canonical_as_array())

    # Adding volumes
    box.set_from_list([1,1,1,  1,0,0,  0,1,0,  0,0,1])
    other = BoundingVolumeBox()
    other.set_from_list([9,9,9,  1,0,0,  0,1,0,  0,0,1])
    print("Consider the two following box bounding volumes:")
    print("    first: ", box.attributes['box'])
    print("   second: ", other.attributes['box'])

    fitting_volume = box.add(other)
    print("When added we get the cube centered at (5,5,5) and with a 5 size:")
    print("   addition result: ", fitting_volume.box)