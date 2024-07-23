import struct
from pathlib import Path

import numpy as np

from py3dtiles.tileset import TileSet


def read_tilesets(paths: list[str]) -> list[TileSet]:
    tilesets = []
    for path in paths:
        tilesets.append(TileSet.from_file(Path(path, 'tileset.json')))
    return tilesets


def attributes_from_gltf(gltf):
    vertices = list()
    uvs = list()
    ids = list()
    colors = list()
    mat_indexes = list()
    binary_blob = gltf.binary_blob()
    for mesh in gltf.meshes:
        for primitive_index, primitive in enumerate(mesh.primitives):
            position_index = primitive.attributes.POSITION
            buffer_view_index = gltf.accessors[position_index].bufferView
            vertex_count = gltf.accessors[position_index].count
            byte_offset = gltf.bufferViews[buffer_view_index].byteOffset + gltf.accessors[position_index].byteOffset
            byte_length = vertex_count * 12
            positions = binary_blob[byte_offset:byte_offset + byte_length]

            for i in range(0, byte_length, 12):
                vertices.append(np.array(struct.unpack('fff', positions[i:i + 12]), dtype=np.float32))

            if primitive.attributes.TEXCOORD_0 is not None:
                texture_index = primitive.attributes.TEXCOORD_0
                buffer_view_index = gltf.accessors[texture_index].bufferView
                tex_count = gltf.accessors[texture_index].count
                byte_offset = gltf.bufferViews[buffer_view_index].byteOffset + gltf.accessors[texture_index].byteOffset
                byte_length = tex_count * 8
                tex_coords = binary_blob[byte_offset:byte_offset + byte_length]

                for i in range(0, byte_length, 8):
                    uvs.append(np.array(struct.unpack('ff', tex_coords[i:i + 8]), dtype=np.float32))

            if primitive.attributes.COLOR_0 is not None:
                color_index = primitive.attributes.COLOR_0
                buffer_view_index = gltf.accessors[color_index].bufferView
                vertex_count = gltf.accessors[color_index].count
                byte_offset = gltf.bufferViews[buffer_view_index].byteOffset + gltf.accessors[color_index].byteOffset
                byte_length = vertex_count * 12
                vertex_colors = binary_blob[byte_offset:byte_offset + byte_length]

                for i in range(0, byte_length, 12):
                    vertices.append(np.array(struct.unpack('fff', vertex_colors[i:i + 12]), dtype=np.float32))

            if primitive.attributes._BATCHID is not None:
                batchid_index = primitive.attributes._BATCHID
                buffer_view_index = gltf.accessors[batchid_index].bufferView
                id_count = gltf.accessors[batchid_index].count
                byte_offset = gltf.bufferViews[buffer_view_index].byteOffset + gltf.accessors[batchid_index].byteOffset
                byte_length = id_count * 4
                batch_ids = [struct.unpack('f', binary_blob[i:i + 4])[0] for i in range(byte_offset, byte_offset + byte_length, 4)]
            else:
                batch_ids = [primitive_index for _ in range(0, vertex_count)]
            for id in batch_ids:
                ids.append(np.array([id, primitive_index], dtype=np.float32))

            mat_indexes.append(primitive.material)

    attributes_dict = {
        'positions': [vertices[n:n + 3] for n in range(0, len(vertices), 3)],
        'ids': ids,
        'mat_indexes': mat_indexes,
        'uvs': [uvs[n:n + 3] for n in range(0, len(uvs), 3)],
        'colors': [colors[n:n + 3] for n in range(0, len(colors), 3)]
    }
    return attributes_dict
