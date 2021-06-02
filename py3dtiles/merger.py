import sys
import os
import numpy as np
import json
from py3dtiles import TileReader
from py3dtiles.points.utils import split_aabb
from py3dtiles.points.transformations import inverse_matrix
from py3dtiles.points.task.pnts_writer import points_to_pnts
from py3dtiles.feature_table import SemanticPoint


def _get_root_tile(tileset, filename):
    folder = os.path.dirname(filename)

    pnts_filename = os.path.join(
        folder,
        tileset['root']['content']['uri'])

    return TileReader().read_file(pnts_filename)


def _get_root_transform(tileset):
    transform = np.identity(4)
    if 'transform' in tileset:
        transform = np.array(tileset['transform']).reshape(4, 4).transpose()

    if 'transform' in tileset['root']:
        transform = np.dot(
            transform,
            np.array(tileset['root']['transform']).reshape(4, 4).transpose())

    return transform


def _get_tile_points(tile, tile_transform, out_transform):
    fth = tile.body.feature_table.header

    xyz = tile.body.feature_table.body.positions_arr.view(
        np.float32).reshape((fth.points_length, 3))
    if fth.colors == SemanticPoint.RGB:
        # rgb = np.array([255, 0, 0] * fth.points_length).reshape((fth.points_length, 3))
        rgb = tile.body.feature_table.body.colors_arr.reshape(
            (fth.points_length, 3)).astype(np.uint8)
    else:
        rgb = None

    x = xyz[:, 0]
    y = xyz[:, 1]
    z = xyz[:, 2]
    w = np.ones(x.shape[0])

    transform = np.dot(out_transform, tile_transform)

    xyzw = np.dot(np.vstack((x, y, z, w)).transpose(), transform.T)

    return xyzw[:, 0:3].astype(np.float32), rgb


def init(files):
    aabb = None
    total_point_count = 0
    tilesets = []
    transforms = []

    idx = 0
    for filename in files:
        with open(filename, 'r') as f:
            tileset = json.load(f)

            tile = _get_root_tile(tileset, filename)
            fth = tile.body.feature_table.header

            # apply transformation
            transform = _get_root_transform(tileset)
            bbox =_aabb_from_3dtiles_bounding_volume(
                tileset['root']['boundingVolume'],
                transform)

            if aabb is None:
                aabb = bbox
            else:
                aabb[0] = np.minimum(aabb[0], bbox[0])
                aabb[1] = np.maximum(aabb[1], bbox[1])

            total_point_count += fth.points_length

            tileset['id'] = idx
            tileset['filename'] = filename
            tileset['center'] = ((bbox[0] + bbox[1]) * 0.5)
            tilesets += [tileset]

            transforms += [transform]

            idx += 1

    return {
        'tilesets': tilesets,
        'aabb': aabb,
        'point_count': total_point_count,
        'transforms': transforms
    }


def quadtree_split(aabb):
    return [
        split_aabb(aabb, 0, True),
        split_aabb(aabb, 2, True),
        split_aabb(aabb, 4, True),
        split_aabb(aabb, 6, True),
    ]


def is_tileset_inside(tileset, aabb):
    return np.all(aabb[0] <= tileset['center']) and np.all(tileset['center'] <= aabb[1])


def _3dtiles_bounding_box_from_aabb(aabb, transform=None):
    if transform is not None:
        aabb = np.dot(aabb, transform.T)
    ab_min = aabb[0]
    ab_max = aabb[1]
    center = (ab_min + ab_max) * 0.5
    half_size = (ab_max - ab_min) * 0.5

    return {
        'box': [
                center[0], center[1], center[2],
                half_size[0], 0, 0,
                0, half_size[1], 0,
                0, 0, half_size[2]]
        }


def _aabb_from_3dtiles_bounding_volume(volume, transform=None):
    center = np.array(volume['box'][0:3])
    h_x_axis = np.array(volume['box'][3:6])
    h_y_axis = np.array(volume['box'][6:9])
    h_z_axis = np.array(volume['box'][9:12])

    amin = (center - h_x_axis - h_y_axis - h_z_axis)
    amax = (center + h_x_axis + h_y_axis + h_z_axis)
    amin.resize((4,))
    amax.resize((4,))
    amin[3] = 1
    amax[3] = 1

    aabb = np.array([amin, amax])

    if transform is not None:
        aabb = np.dot(aabb, transform.T)

    return aabb



def build_tileset_quadtree(out_folder, aabb, tilesets, base_transform, inv_base_transform, name):
    insides = []

    for tileset in tilesets:
        if is_tileset_inside(tileset, aabb):
            insides += [tileset]

    quadtree_diag = np.linalg.norm(aabb[1][:2] - aabb[0][:2])

    if not insides:
        return None
    elif len(insides) == 1 or quadtree_diag < 1:
        # apply transform to boundingVolume
        box = _aabb_from_3dtiles_bounding_volume(
            insides[0]['root']['boundingVolume'],
            _get_root_transform(insides[0]))

        return {
            'transform': inv_base_transform.T.reshape(16).tolist(),
            'geometricError': insides[0]['root']['geometricError'],
            'boundingVolume': _3dtiles_bounding_box_from_aabb(box),
            'content': {
                'uri': os.path.relpath(insides[0]['filename'], out_folder)
            }
        }
    else:
        tilesets = [t for t in tilesets if t['id'] not in insides]
        result = {
            'children': []
        }

        sub = 0
        for quarter in quadtree_split(aabb):
            r = build_tileset_quadtree(out_folder, quarter, insides, base_transform, inv_base_transform, name + str(sub))
            sub += 1
            if r is not None:
                result['children'] += [r]

        union_aabb = _aabb_from_3dtiles_bounding_volume(
            insides[0]['root']['boundingVolume'],
            _get_root_transform(insides[0]))
        # take half points from our children
        xyz = np.zeros((0, 3), dtype=np.float32)
        rgb = np.zeros((0, 3), dtype=np.uint8)

        max_point_count = 50000
        point_count = 0
        for tileset in insides:
            root_tile = _get_root_tile(tileset, tileset['filename'])
            point_count += root_tile.body.feature_table.header.points_length

        ratio = min(0.5, max_point_count / point_count)

        for tileset in insides:
            root_tile = _get_root_tile(tileset, tileset['filename'])
            _xyz, _rgb = _get_tile_points(root_tile, _get_root_transform(tileset), inv_base_transform)
            select = np.random.choice(_xyz.shape[0], int(_xyz.shape[0] * ratio))
            xyz = np.concatenate((xyz, _xyz[select]))
            if _rgb is not None:
                rgb = np.concatenate((rgb, _rgb[select]))

            ab = _aabb_from_3dtiles_bounding_volume(
                tileset['root']['boundingVolume'],
                _get_root_transform(tileset))
            union_aabb[0] = np.minimum(union_aabb[0], ab[0])
            union_aabb[1] = np.maximum(union_aabb[1], ab[1])

        filename = points_to_pnts(
            name.encode('ascii'),
            np.concatenate((xyz.view(np.uint8).ravel(), rgb.ravel())),
            out_folder,
            rgb.shape[0] > 0)[1]
        result['content'] = { 'uri': os.path.relpath(filename, out_folder) }
        result['geometricError'] = sum([t['root']['geometricError'] for t in insides])
        result['boundingVolume'] = _3dtiles_bounding_box_from_aabb(union_aabb, inv_base_transform)

        return result


def extract_content_uris(tileset):
    contents = []
    for key in tileset:
        if key == 'content':
            contents += [tileset[key]['uri']]
        elif key == 'children':
            for child in tileset['children']:
                contents += extract_content_uris(child)
        elif key == 'root':
            contents += extract_content_uris(tileset['root'])

    return contents


def remove_tileset(tileset_filename):
    folder = os.path.dirname(tileset_filename)
    with open(tileset_filename, 'r') as f:
        tileset = json.load(f)
    contents = extract_content_uris(tileset)
    for content in contents:
        ext = os.path.splitext(content)[1][1:]
        if ext == 'pnts':
            os.remove('{}/{}'.format(folder, content))
        elif ext == 'json':
            # remove_tileset('{}/{}'.format(folder, content))
            pass
        else:
            raise Exception('unknown extension {}'.format(ext))
    os.remove(tileset_filename)


def init_parser(subparser, str2bool):
    parser = subparser.add_parser('merge', help='Merge several pointcloud tilesets in 1 tileset')
    parser.add_argument(
        'folder',
        help='Folder with tileset.json files')
    parser.add_argument(
        '--overwrite',
        help='Overwrite the ouput folder if it already exists.',
        default=False,
        type=str2bool)


def main(args):
    dest = '{}/tileset.json'.format(args.folder)
    if os.path.exists(dest):
        if args.overwrite:
            remove_tileset(dest)
        else:
            print('Destination tileset {} already exists. Aborting'.format(dest))
            sys.exit(1)

    tilesets = []
    for root, dirs, files in os.walk(args.folder):
        t = ['{}/{}'.format(root, f) for f in files if f == 'tileset.json']
        if t:
            tilesets += t

    if args.verbose >= 1:
        print('Found {} tilesets to merge'.format(len(tilesets)))
    if args.verbose >= 2:
        print('Tilesets:', tilesets)

    infos = init(tilesets)

    aabb = infos['aabb']

    base_transform = infos['transforms'][0]

    inv_base_transform = inverse_matrix(base_transform)
    print('------------------------')
    # build hierarchical structure
    result = build_tileset_quadtree(args.folder, aabb, infos['tilesets'], base_transform, inv_base_transform, '')

    result['transform'] = base_transform.T.reshape(16).tolist()
    tileset = {
        'asset': {
            'version': '1.0'
        },
        'refine': 'REPLACE',
        'geometricError': np.linalg.norm((aabb[1] - aabb[0])[0:3]),
        'root': result
    }

    with open('{}/tileset.json'.format(args.folder), 'w') as f:
        json.dump(tileset, f)


if __name__ == '__main__':
    main()
