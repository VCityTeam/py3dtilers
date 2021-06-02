import os
import time
import traceback
import pickle
import struct

from py3dtiles.points.node_catalog import NodeCatalog


def _forward_unassigned_points(node, queue, log_file):
    total = 0

    result = node.dump_pending_points()

    for r in result:
        if len(r) > 0:
            if log_file is not None:
                print('    -> put on queue ({},{})'.format(r[0], r[2]), file=log_file)
            total += r[2]
            queue.send_multipart([
                r[0],
                r[1],
                struct.pack('>I', r[2])], copy=False, block=False)

    return total


def _flush(node_catalog, scale, node, queue, max_depth=1, force_forward=False, log_file=None, depth=0):
    if depth >= max_depth:
        threshold = 0 if force_forward else 10000
        if node.get_pending_points_count() > threshold:
            return _forward_unassigned_points(node, queue, log_file)
        else:
            return 0

    node.flush_pending_points(node_catalog, scale)

    total = 0
    if node.children is not None:
        # then flush children
        children = node.children
        # release node
        del node
        for name in children:
            total += _flush(node_catalog, scale, node_catalog.get_node(name), queue, max_depth, force_forward, log_file, depth + 1)

    return total

def _balance(node_catalog, node, max_depth=1, depth=0):
    if depth >= max_depth:
        return 0

    if node.needs_balance():
        node.grid.balance(node.aabb_size, node.aabb[0], node.inv_aabb_size)
        node.dirty = True

    if node.children is not None:
        # then _flush children
        children = node.children
        # release node
        del node
        for name in children:
            _balance(
                node_catalog,
                node_catalog.get_node(name),
                max_depth,
                depth + 1)


def _process(nodes, octree_metadata, name, raw_datas, queue, begin, log_file):
    node_catalog = NodeCatalog(nodes, name, octree_metadata)

    log_enabled = log_file is not None

    if log_enabled:
        print('[>] process_node: "{}", {}'.format(
            name, len(raw_datas), file=log_file, flush=True))

    node = node_catalog.get_node(name)

    halt_at_depth = 0
    if len(name) >= 7:
        halt_at_depth = 5
    elif len(name) >= 5:
        halt_at_depth = 3
    elif len(name) > 2:
        halt_at_depth = 2
    elif len(name) >= 1:
        halt_at_depth = 1

    total = 0
    index = 0

    for raw_data in raw_datas:
        if log_enabled:
            print('  -> read source [{}]'.format(time.time() - begin), file=log_file, flush=True)

        data = pickle.loads(raw_data)

        point_count = len(data['xyz'])

        if log_enabled:
            print('  -> insert {} [{} points]/ {} files [{}]'.format(
                index + 1, point_count,
                len(raw_datas), time.time() - begin), file=log_file, flush=True)

        # insert points in node (no children handling here)
        node.insert(node_catalog, octree_metadata.scale, data['xyz'], data['rgb'], halt_at_depth == 0)

        total += point_count

        if log_enabled:
            print('  -> _flush [{}]'.format(time.time() - begin), file=log_file, flush=True)
        # _flush push pending points (= call insert) from level N to level N + 1
        # (_flush is recursive)
        written = _flush(node_catalog, octree_metadata.scale, node, queue, halt_at_depth - 1, index == len(raw_datas) - 1, log_file)
        total -= written

        index += 1

    _balance(node_catalog, node, halt_at_depth - 1)

    if log_enabled:
        print('save on disk {} [{}]'.format(name, time.time() - begin), file=log_file)

    # save node state on disk
    data = b''
    if halt_at_depth > 0:
        data = node_catalog.dump(name, halt_at_depth - 1)

    if log_enabled:
        print('saved on disk [{}]'.format(time.time() - begin), file=log_file)

    return (total, data)


def run(work, octree_metadata, queue, verbose):
    try:
        begin = time.time()
        log_enabled = verbose >= 2
        if log_enabled:
            log_filename = 'py3dtiles-{}.log'.format(os.getpid())
            log_file = open(log_filename, 'a')
        else:
            log_file = None

        total = 0

        i = 0
        while i < len(work):
            name = work[i]
            node = work[i + 1]
            count = struct.unpack('>I', work[i + 2])[0]
            filenames = work[i + 3:i + 3 + count]
            i += 3 + count
            result, data = _process(node, octree_metadata, name, filenames, queue, begin, log_file)
            total += result

            queue.send_multipart([pickle.dumps({
                'name': name,
                'total': result,
                'save': data,
            })], copy=False)

        if log_enabled:
            print('[<] return result [{} sec] [{}]'.format(
                round(time.time() - begin, 2),
                time.time() - begin), file=log_file, flush=True)
            if log_file is not None:
                log_file.close()

        # notify we're idle
        queue.send_multipart([b''])

        return total

    except Exception as e:
        if log_enabled or True:
            print('OH NO. {}'.format(name))
        if log_enabled or True:
            print(e)
        if log_enabled or True:
            traceback.print_exc()

    return 0
