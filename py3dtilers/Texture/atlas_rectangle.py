class Rectangle(object):
    """
    The class that represents a rectangle in the atlas by its position, width
    and height.
    """

    def __init__(self, left, top, right, bottom):
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
        self.width = right - left
        self.height = bottom - top

    def setSize(self, newWidth, newHeight):
        self.width = newWidth
        self.height = newHeight

    def get_top(self):
        return self.top

    def get_bottom(self):
        return self.bottom

    def get_right(self):
        return self.right

    def get_left(self):
        return self.left

    def get_width(self):
        return self.width

    def get_height(self):
        return self.height

    def fits(self, img):
        """
        :param img: A pillow image
        :rtype boolean: Whether the image fits in the rectangle or no
                        i.e if the image is smaller than the rectangle
        """
        imageWidth, imageHeight = img.size
        return imageWidth <= self.width and imageHeight <= self.height

    def perfect_fits(self, img):
        """
        :param img: A pillow image
        :rtype boolean: Whether the image prefectly fits in the rectangle or no,
                    i.e if the image have the exact same size of the rectangle
        """
        imageWidth, imageHeight = img.size
        return imageWidth == self.width and imageHeight == self.height
