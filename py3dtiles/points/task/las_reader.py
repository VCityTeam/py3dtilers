import numpy as np
import math
import traceback
import laspy
import pyproj
import struct
from laspy.file import File
import liblas
from pickle import dumps as pdumps


def init(args):
    aabb = None
    total_point_count = 0
    pointcloud_file_portions = []
    avg_min = np.array([0., 0., 0.])
    color_scale = args.color_scale if 'color_scale' in args else None

    input_srs = args.srs_in

    for filename in args.files:
        try:
            f = File(filename, mode='r')
        except Exception as e:
            print('Error opening {filename}. Skipping.'.format(**locals()))
            print(e)
            continue
        avg_min += (np.array(f.header.min) / len(args.files))

        if aabb is None:
            aabb = np.array([f.header.get_min(), f.header.get_max()])
        else:
            bb = np.array([f.header.get_min(), f.header.get_max()])
            aabb[0] = np.minimum(aabb[0], bb[0])
            aabb[1] = np.maximum(aabb[1], bb[1])

        count = int(f.header.count * args.fraction / 100)
        total_point_count += count

        # read the first points red channel
        if color_scale is None:
            if 'red' in f.point_format.lookup:
                color_test_field = 'red'
                if np.max(f.get_points()['point'][color_test_field][0:min(10000, f.header.count)]) > 255:
                        color_scale = 1.0 / 255
            else:
                color_test_field = 'intensity'
                color_scale = 1.0 / 255


        _1M = min(count, 1000000)
        steps = math.ceil(count / _1M)
        portions = [(i * _1M, min(count, (i + 1) * _1M)) for i in range(steps)]
        for p in portions:
            pointcloud_file_portions += [(filename, p)]

        if (args.srs_out is not None and
                input_srs is None):
            f = liblas.file.File(filename)
            if (f.header.srs.proj4 is not None and
                f.header.srs.proj4 != ''):
                input_srs = pyproj.Proj(f.header.srs.proj4)
            else:
                raise Exception('\'{}\' file doesn\'t contain srs information. Please use the --srs_in option to declare it.'.format(filename))

    return {
        'portions': pointcloud_file_portions,
        'aabb': aabb,
        'color_scale': color_scale,
        'srs_in': input_srs,
        'point_count': total_point_count,
        'avg_min': avg_min
    }



def run(_id, filename, offset_scale, portion, queue, projection, verbose):
    '''
    Reads points from a las file
    '''
    try:
        f = laspy.file.File(filename, mode='r')

        point_count = portion[1] - portion[0]

        step = min(point_count, max((point_count) // 10, 100000))

        indices = [i for i in range(math.ceil((point_count) / step))]

        color_scale = offset_scale[3]

        file_points = f.get_points()['point']
        X = file_points['X']
        Y = file_points['Y']
        Z = file_points['Z']
        # todo: attributes
        if 'red' in f.point_format.lookup:
            RED = file_points['red']
            GREEN = file_points['green']
            BLUE = file_points['blue']
        else:
            RED = file_points['intensity']
            GREEN = file_points['intensity']
            BLUE = file_points['intensity']

        for index in indices:
            start_offset = portion[0] + index * step
            num = min(step, portion[1] - start_offset)

            # read scaled values and apply offset
            x = X[start_offset:start_offset + num] * f.header.scale[0] + f.header.offset[0]
            y = Y[start_offset:start_offset + num] * f.header.scale[1] + f.header.offset[1]
            z = Z[start_offset:start_offset + num] * f.header.scale[2] + f.header.offset[2]

            if projection:
                x, y, z = pyproj.transform(projection[0], projection[1], x, y, z)

            x = (x + offset_scale[0][0]) * offset_scale[1][0]
            y = (y + offset_scale[0][1]) * offset_scale[1][1]
            z = (z + offset_scale[0][2]) * offset_scale[1][2]

            coords = np.vstack((x, y, z)).transpose()

            if offset_scale[2] is not None:
                # Apply transformation matrix (because the tile's transform will contain
                # the inverse of this matrix)
                coords = np.dot(coords, offset_scale[2])

            coords = np.ascontiguousarray(coords.astype(np.float32))

            # Read colors
            red = RED[start_offset:start_offset + num]
            green = GREEN[start_offset:start_offset + num]
            blue = BLUE[start_offset:start_offset + num]

            if color_scale is None:
                red = red.astype(np.uint8)
                green = green.astype(np.uint8)
                blue = blue.astype(np.uint8)
            else:
                red = (red * color_scale).astype(np.uint8)
                green = (green * color_scale).astype(np.uint8)
                blue = (blue * color_scale).astype(np.uint8)

            colors = np.vstack((red, green, blue)).transpose()

            result = (''.encode('ascii'), pdumps({'xyz': coords, 'rgb': colors}), len(coords))
            queue.send_multipart([
                ''.encode('ascii'),
                pdumps({'xyz': coords, 'rgb': colors}),
                struct.pack('>I', len(coords))], copy=False)

        queue.send_multipart([pdumps({ 'name': _id, 'total': 0 })])
        # notify we're idle
        queue.send_multipart([b''])

        f.close()
    except Exception as e:
        print('Exception while reading points from las file')
        print(e)
        traceback.print_exc()
