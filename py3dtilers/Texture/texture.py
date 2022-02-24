import numpy as np
from PIL import Image


class Texture():
    """
    A Texture contains a Pillow Image.
    A Texture can be cropped.
    """

    folder = None

    def __init__(self, image_path):
        """
        :param image_path: path to the image (or a stream with image bytes)
        Create a pillow.image:
        """
        self.image = Image.open(image_path)

    def get_cropped_texture_image(self, uvs):
        """
        Return a part of the original image.
        The original is cropped to keep only the area defined by the UVs.
        :param uvs: the uvs
        :return: a Pillow Image
        """
        image = self.cropImage(self.image, uvs)
        return image.convert("RGBA")

    def cropImage(self, image, uvs):
        """
        Crop the image to keep the area defined by the uvs.
        :param image: the Pillow Image to crop.
        :param uvs: the uvs defining the area.
        :return: a Pillow Image
        """
        minX = 2
        maxX = -1

        minY = 2
        maxY = -1

        texture_size = image.size
        for uv_triangle in uvs:
            for uv in uv_triangle:
                if uv[0] < minX:
                    minX = uv[0]
                if uv[0] > maxX:
                    maxX = uv[0]
                if uv[1] < minY:
                    minY = uv[1]
                if uv[1] > maxY:
                    maxY = uv[1]

        cropped_image = image.crop((minX * texture_size[0], minY * texture_size[1], maxX * texture_size[0], maxY * texture_size[1]))

        self.updateUvs(uvs, [minX, minY, maxX, maxY])
        return cropped_image

    def updateUvs(self, uvs, rect):
        """
        Update the UVs to match the new ratio.
        :param uvs: the uvs
        :param rect: the area (minX, minY, maxX, maxY)
        """
        offsetX = rect[0]
        offsetY = rect[1]
        if rect[2] != rect[0]:
            ratioX = 1 / (rect[2] - rect[0])
        else:
            ratioX = 1
        if rect[3] != rect[1]:
            ratioY = 1 / (rect[3] - rect[1])
        else:
            ratioY = 1

        for i in range(0, len(uvs)):
            for y in range(0, 3):
                new_u = (uvs[i][y][0] - offsetX) * ratioX
                new_v = (uvs[i][y][1] - offsetY) * ratioY
                # warning : in order to be written correctly, the GLTF writter
                # expects data to be in float32
                uvs[i][y] = np.array([new_u, new_v], dtype=np.float32)

    @staticmethod
    def get_texture_folder():
        return Texture.folder

    @staticmethod
    def set_texture_folder(folder):
        Texture.folder = folder
