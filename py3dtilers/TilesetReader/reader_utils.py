import struct
from pathlib import Path

import numpy as np

from py3dtiles.tileset import TileSet
from py3dtiles.tilers.b3dm.wkb_utils import TriangleSoup


def read_tilesets(paths: list[str]) -> list[TileSet]:
    tilesets = []
    for path in paths:
        tilesets.append(TileSet.from_file(Path(path, 'tileset.json')))
    return tilesets


def triangle_soup_from_gltf(gltf):
    header = gltf.header
    vertices = list()
    uvs = list()
    ids = list()
    mat_indexes = list()
    for mesh_index, mesh in enumerate(header['meshes']):
        position_index = mesh['primitives'][0]['attributes']['POSITION']
        buffer_index = header['accessors'][position_index]['bufferView']
        vertex_count = header['accessors'][position_index]['count']
        byte_offset = header['bufferViews'][buffer_index]['byteOffset'] + header['accessors'][position_index]['byteOffset']
        byte_length = vertex_count * 12
        positions = gltf.body[byte_offset:byte_offset + byte_length]

        for i in range(0, byte_length, 12):
            vertices.append(np.array(struct.unpack('fff', positions[i:i + 12].tobytes()), dtype=np.float32))

        if 'TEXCOORD_0' in mesh['primitives'][0]['attributes']:
            texture_index = mesh['primitives'][0]['attributes']['TEXCOORD_0']
            buffer_index = header['accessors'][texture_index]['bufferView']
            tex_count = header['accessors'][texture_index]['count']
            byte_offset = header['bufferViews'][buffer_index]['byteOffset'] + header['accessors'][texture_index]['byteOffset']
            byte_length = tex_count * 8
            tex_coords = gltf.body[byte_offset:byte_offset + byte_length]

            for i in range(0, byte_length, 8):
                uvs.append(np.array(struct.unpack('ff', tex_coords[i:i + 8].tobytes()), dtype=np.float32))

        if '_BATCHID' in mesh['primitives'][0]['attributes']:
            batchid_index = mesh['primitives'][0]['attributes']['_BATCHID']
            buffer_index = header['accessors'][batchid_index]['bufferView']
            id_count = header['accessors'][batchid_index]['count']
            byte_offset = header['bufferViews'][buffer_index]['byteOffset'] + header['accessors'][batchid_index]['byteOffset']
            byte_length = id_count * 4
            batch_ids = [struct.unpack('f', gltf.body[i:i + 4].tobytes())[0] for i in range(byte_offset, byte_offset + byte_length, 4)]
        else:
            batch_ids = [mesh_index for i in range(0, vertex_count)]
        for id in batch_ids:
            ids.append(np.array([id, mesh_index], dtype=np.float32))

        mat_indexes.append(mesh['primitives'][0]['material'])

    ts = TriangleSoup()
    ts.triangles.append([vertices[n:n + 3] for n in range(0, len(vertices), 3)])
    ts.triangles.append(ids)
    ts.triangles.append(np.array(mat_indexes, dtype=np.float32))
    if len(uvs) > 0:
        ts.triangles.append([uvs[n:n + 3] for n in range(0, len(uvs), 3)])

    return ts
