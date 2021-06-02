import os
import shutil
import sys
import time
import multiprocessing
import numpy as np
import json
from collections import namedtuple
import pickle
import zmq
import pyproj
import psutil
import struct
import concurrent.futures
import argparse
from py3dtiles.points.transformations import rotation_matrix, angle_between_vectors, vector_product, inverse_matrix, scale_matrix, translation_matrix
from py3dtiles.points.utils import compute_spacing, name_to_filename
from py3dtiles.points.node import Node
from py3dtiles import TileReader
from py3dtiles.points.shared_node_store import SharedNodeStore
import py3dtiles.points.task.las_reader as las_reader
import py3dtiles.points.task.node_process as node_process
import py3dtiles.points.task.pnts_writer as pnts_writer


def write_tileset(in_folder, out_folder, octree_metadata, offset, scale, projection, rotation_matrix, include_rgb):
    # compute tile transform matrix
    if rotation_matrix is None:
        transform = np.identity(4)
    else:
        transform = inverse_matrix(rotation_matrix)
    transform = np.dot(transform, scale_matrix(1.0 / scale[0]))
    transform = np.dot(translation_matrix(offset), transform)

    # build fake points
    if True:
        root_node = Node('', octree_metadata.aabb, octree_metadata.spacing * 2)
        root_node.children = []
        inv_aabb_size = (1.0 / (octree_metadata.aabb[1] - octree_metadata.aabb[0])).astype(np.float32)
        for child in ['0', '1', '2', '3', '4', '5', '6', '7']:
            ondisk_tile = name_to_filename(out_folder, child.encode('ascii'), '.pnts')
            if os.path.exists(ondisk_tile):
                tile = TileReader().read_file(ondisk_tile)
                th = tile.header
                fth = tile.body.feature_table.header
                xyz = tile.body.feature_table.body.positions_arr.view(np.float32).reshape((fth.points_length, 3))
                if include_rgb:
                    rgb = tile.body.feature_table.body.colors_arr.reshape((fth.points_length, 3))
                else:
                    rgb = np.zeros(xyz.shape, dtype=np.uint8)

                root_node.grid.insert(
                    octree_metadata.aabb[0].astype(np.float32),
                    inv_aabb_size,
                    xyz.copy(),
                    rgb)

        pnts_writer.node_to_pnts(''.encode('ascii'), root_node, out_folder, include_rgb)

    executor = concurrent.futures.ProcessPoolExecutor()
    root_tileset = Node.to_tileset(executor, ''.encode('ascii'), octree_metadata.aabb, octree_metadata.spacing, out_folder, scale)
    executor.shutdown()

    root_tileset['transform'] = transform.T.reshape(16).tolist()
    root_tileset['refine'] = 'REPLACE'
    for child in root_tileset['children']:
        child['refine'] = 'ADD'

    tileset = {
        'asset': {
            'version': '1.0',
        },
        'geometricError': np.linalg.norm(
            octree_metadata.aabb[1] - octree_metadata.aabb[0]) / scale[0],
        'root': root_tileset,
    }

    with open('{}/tileset.json'.format(out_folder), 'w') as f:
        f.write(json.dumps(tileset))


def make_rotation_matrix(z1, z2):
    v0 = z1 / np.linalg.norm(z1)
    v1 = z2 / np.linalg.norm(z2)

    return rotation_matrix(
        angle_between_vectors(v0, v1),
        vector_product(v0, v1))


OctreeMetadata = namedtuple('OctreeMetadata', ['aabb', 'spacing', 'scale'])


def zmq_process(activity_graph, projection, node_store, octree_metadata, folder, write_rgb, verbosity):
    context = zmq.Context()

    # Socket to receive messages on
    skt = context.socket(zmq.DEALER)
    skt.connect('ipc:///tmp/py3dtiles1')

    startup_time = time.time()
    idle_time = 0

    if activity_graph:
        activity = open('activity.{}.csv'.format(os.getpid()), 'w')

    # notify we're ready
    skt.send_multipart([b''])

    while True:
        before = time.time() - startup_time

        skt.poll()

        after = time.time() - startup_time

        idle_time += after - before
        command = skt.recv_multipart()
        delta = time.time() - pickle.loads(command[0])
        if delta > 0.01 and verbosity >= 1:
            print('{} / {} : Delta time: {}'.format(os.getpid(), round(after, 2), round(delta, 3)))
        command = command[1:]

        if len(command) == 1:
            command = pickle.loads(command[0])
            command_type = 1

            if command == b'shutdown':
                # ack
                break

            las_reader.run(
                command['id'],
                command['filename'],
                command['offset_scale'],
                command['portion'],
                skt,
                projection,
                verbosity)
        elif command[0] == b'pnts':
            command_type = 3
            pnts_writer.run(skt, command[2], command[1], folder, write_rgb)
            skt.send_multipart([b''])
        else:
            command_type = 2
            node_process.run(
                command,
                octree_metadata,
                skt,
                verbosity)

        if activity_graph:
            print('{before}, {command_type}'.format(**locals()), file=activity)
            print('{before}, 0'.format(**locals()), file=activity)
            print('{after}, 0'.format(**locals()), file=activity)
            print('{after}, {command_type}'.format(**locals()), file=activity)

    if activity_graph:
        activity.close()

    if verbosity >= 1:
        print('total: {} sec, idle: {}'.format(
            round(time.time() - startup_time, 1),
            round(idle_time, 1)))

    skt.send_multipart([b'halted'])


def zmq_send_to_process(idle_clients, socket, message):
    assert idle_clients
    socket.send_multipart([idle_clients.pop(), pickle.dumps(time.time())] + message)


def zmq_send_to_all_process(idle_clients, socket, message):
    assert idle_clients
    for client in idle_clients:
        socket.send_multipart([client, pickle.dumps(time.time())] + message)
    idle_clients.clear()


def is_ancestor(ln, la, name, ancestor):
    return la <= ln and name[0:la] == ancestor


def is_ancestor_in_list(ln, node_name, d):
    for ancestor in d:
        k_len = len(ancestor)
        if k_len == 0:
            return True
        if is_ancestor(ln, k_len, node_name, ancestor):
            return True
    return False


def can_pnts_be_written(name, finished_node, input_nodes, active_nodes):
    ln = len(name)
    return (
        is_ancestor(ln, len(finished_node), name, finished_node) and
        not is_ancestor_in_list(ln, name, active_nodes) and
        not is_ancestor_in_list(ln, name, input_nodes))


LasReader = namedtuple('LasReader', ['input', 'active'])
NodeProcess = namedtuple('NodeProcess', ['input', 'active', 'inactive'])
ToPnts = namedtuple('ToPnts', ['input', 'active'])


class State():
    def __init__(self, pointcloud_file_portions):
        self.las_reader = LasReader(input=pointcloud_file_portions, active=[])
        self.node_process = NodeProcess(input={}, active={}, inactive=[])
        self.to_pnts = ToPnts(input=[], active=[])

    def print_debug(self):
        print('{:^16}|{:^8}|{:^8}|{:^8}'.format('Step', 'Input', 'Active', 'Inactive'))
        print('{:^16}|{:^8}|{:^8}|{:^8}'.format(
            'LAS reader',
            len(self.las_reader.input),
            len(self.las_reader.active),
            ''))
        print('{:^16}|{:^8}|{:^8}|{:^8}'.format(
            'Node process',
            len(self.node_process.input),
            len(self.node_process.active),
            len(self.node_process.inactive)))
        print('{:^16}|{:^8}|{:^8}|{:^8}'.format(
            'Pnts writer',
            len(self.to_pnts.input),
            len(self.to_pnts.active),
            ''))


def can_queue_more_jobs(idles):
    return idles


def init_parser(subparser, str2bool):
    total_memory_MB = int(psutil.virtual_memory().total / (1024 * 1024))

    parser = subparser.add_parser(
        'convert',
        help='Convert .las files to a 3dtiles tileset.',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument(
        'files',
        nargs='+',
        help='Filenames to process. The file must use the .las format.')
    parser.add_argument(
        '--out',
        type=str,
        help='The folder where the resulting tileset will be written.',
        default='./3dtiles')
    parser.add_argument(
        '--overwrite',
        help='Overwrite the ouput folder if it already exists.',
        default=False,
        type=str2bool)
    parser.add_argument(
        '--jobs',
        help='The number of parallel jobs to start.',
        default=multiprocessing.cpu_count(),
        type=int)
    parser.add_argument(
        '--cache_size',
        help='Cache size in MB',
        default=int(total_memory_MB / 10),
        type=int)
    parser.add_argument(
        '--srs_out', help='SRS to use as output (EPSG code)', type=str)
    parser.add_argument(
        '--srs_in', help='Override input SRS (EPSG code)', type=str)
    parser.add_argument(
        '--fraction',
        help='Percentage of the pointcloud to process.',
        default=100, type=int)
    parser.add_argument(
        '--benchmark',
        help='Print summary at the end of the process', type=str)
    parser.add_argument(
        '--rgb',
        help='Export rgb attributes', type=str2bool, default=True)
    parser.add_argument(
        '--graph',
        help='Produce debug graphes (requires pygal)', type=str2bool, default=False)
    parser.add_argument(
        '--color_scale',
        help='Force color scale', type=float)


def main(args):
    folder = args.out

    # create folder
    if os.path.isdir(folder):
        if args.overwrite:
            shutil.rmtree(folder)
        else:
            print('Error, folder \'{}\' already exists'.format(folder))
            sys.exit(1)

    os.makedirs(folder)
    working_dir = folder + '/tmp'
    os.makedirs(working_dir)

    node_store = SharedNodeStore(working_dir)

    # read all input files headers and determine the aabb/spacing
    infos = las_reader.init(args)

    avg_min = infos['avg_min']
    rotation_matrix = None
    # srs stuff
    projection = None
    if args.srs_out is not None:
        p2 = pyproj.Proj(init='epsg:{}'.format(args.srs_out))
        if args.srs_in is not None:
            p1 = pyproj.Proj(init='epsg:{}'.format(args.srs_in))
        else:
            p1 = infos['srs_in']
        projection = [p1, p2]

        bl = np.array(list(pyproj.transform(
            projection[0], projection[1],
            infos['aabb'][0][0], infos['aabb'][0][1], infos['aabb'][0][2])))
        tr = np.array(list(pyproj.transform(
            projection[0], projection[1],
            infos['aabb'][1][0], infos['aabb'][1][1], infos['aabb'][1][2])))
        br = np.array(list(pyproj.transform(
            projection[0], projection[1],
            infos['aabb'][1][0], infos['aabb'][0][1], infos['aabb'][0][2])))

        avg_min = np.array(list(pyproj.transform(
            projection[0], projection[1],
            avg_min[0], avg_min[1], avg_min[2])))

        x_axis = br - bl

        bl = bl - avg_min
        tr = tr - avg_min

        if args.srs_out == '4978':
            # Transform geocentric normal => (0, 0, 1)
            # and 4978-bbox x axis => (1, 0, 0),
            # to have a bbox in local coordinates that's nicely aligned with the data
            rotation_matrix = make_rotation_matrix(avg_min, np.array([0, 0, 1]))
            rotation_matrix = np.dot(
                make_rotation_matrix(x_axis, np.array([1, 0, 0])),
                rotation_matrix)

            bl = np.dot(bl, rotation_matrix[:3, :3].T)
            tr = np.dot(tr, rotation_matrix[:3, :3].T)

        root_aabb = np.array([
            np.minimum(bl, tr),
            np.maximum(bl, tr)
        ])
    else:
        # offset
        root_aabb = infos['aabb'] - avg_min

    original_aabb = root_aabb

    if True:
        base_spacing = compute_spacing(root_aabb)
        if base_spacing > 10:
            root_scale = np.array([0.01, 0.01, 0.01])
        elif base_spacing > 1:
            root_scale = np.array([0.1, 0.1, 0.1])
        else:
            root_scale = np.array([1.0, 1.0, 1.0])

    root_aabb = root_aabb * root_scale
    root_spacing = compute_spacing(root_aabb)

    octree_metadata = OctreeMetadata(aabb=root_aabb, spacing=root_spacing, scale=root_scale[0])

    if args.verbose >= 1:
        print('Summary:')
        print('  - points to process: {}'.format(infos['point_count']))
        print('  - offset to use: {}'.format(avg_min))
        print('  - root spacing: {}'.format(root_spacing / root_scale[0]))
        print('  - root aabb: {}'.format(root_aabb))
        print('  - original aabb: {}'.format(original_aabb))

    startup = time.time()

    initial_portion_count = len(infos['portions'])

    if args.graph:
        progression_log = open('progression.csv', 'w')

    def add_tasks_to_process(state, name, task, point_count):
        assert point_count > 0
        tasks_to_process = state.node_process.input
        if name not in tasks_to_process:
            tasks_to_process[name] = ([task], point_count)
        else:
            tasks, count = tasks_to_process[name]
            tasks.append(task)
            tasks_to_process[name] = (tasks, count + point_count)

    processed_points = 0
    points_in_progress = 0
    previous_percent = 0
    points_in_pnts = 0

    max_splitting_jobs_count = max(1, args.jobs // 2)

    # zmq setup
    context = zmq.Context()

    zmq_skt = context.socket(zmq.ROUTER)
    zmq_skt.bind('ipc:///tmp/py3dtiles1')

    zmq_idle_clients = []

    state = State(infos['portions'])

    zmq_processes_killed = -1

    zmq_processes = [multiprocessing.Process(
        target=zmq_process,
        args=(
            args.graph, projection, node_store, octree_metadata, folder, args.rgb, args.verbose)) for i in range(args.jobs)]

    for p in zmq_processes:
        p.start()
    activities = [p.pid for p in zmq_processes]

    time_waiting_an_idle_process = 0

    while True:
        # state.print_debug()
        now = time.time() - startup
        at_least_one_job_ended = False

        all_processes_busy = not can_queue_more_jobs(zmq_idle_clients)
        while all_processes_busy or zmq_skt.poll(timeout=0, flags=zmq.POLLIN):
            # Blocking read but it's fine because either all our child processes are busy
            # or we know that there's something to read (zmq.POLLIN)
            start = time.time()
            result = zmq_skt.recv_multipart()

            client_id = result[0]
            result = result[1:]

            if len(result) == 1:
                if len(result[0]) == 0:
                    assert client_id not in zmq_idle_clients
                    zmq_idle_clients += [client_id]

                    if all_processes_busy:
                        time_waiting_an_idle_process += time.time() - start
                    all_processes_busy = False
                elif result[0] == b'halted':
                    zmq_processes_killed += 1
                    all_processes_busy = False
                else:
                    result = pickle.loads(result[0])
                    processed_points += result['total']
                    points_in_progress -= result['total']

                    if 'save' in result and len(result['save']) > 0:
                        node_store.put(result['name'], result['save'])

                    if result['name'][0:4] == b'root':
                        state.las_reader.active.remove(result['name'])
                    else:
                        del state.node_process.active[result['name']]

                        if len(result['name']) > 0:
                            state.node_process.inactive.append(result['name'])

                            if not state.las_reader.input and not state.las_reader.active:
                                if state.node_process.active or state.node_process.input:
                                    finished_node = result['name']
                                    if not can_pnts_be_written(
                                            finished_node,
                                            finished_node,
                                            state.node_process.input,
                                            state.node_process.active):
                                        pass
                                    else:
                                        state.node_process.inactive.pop(-1)
                                        state.to_pnts.input.append(finished_node)

                                        for i in range(len(state.node_process.inactive) - 1, -1, -1):
                                            candidate = state.node_process.inactive[i]

                                            if can_pnts_be_written(
                                                    candidate, finished_node,
                                                    state.node_process.input,
                                                    state.node_process.active):
                                                state.node_process.inactive.pop(i)
                                                state.to_pnts.input.append(candidate)

                                else:
                                    for c in state.node_process.inactive:
                                        state.to_pnts.input.append(c)
                                    state.node_process.inactive.clear()

                    at_least_one_job_ended = True
            elif result[0] == b'pnts':
                points_in_pnts += struct.unpack('>I', result[1])[0]
                state.to_pnts.active.remove(result[2])
            else:
                count = struct.unpack('>I', result[2])[0]
                add_tasks_to_process(state, result[0], result[1], count)


        while state.to_pnts.input and can_queue_more_jobs(zmq_idle_clients):
            node_name = state.to_pnts.input.pop()
            datas = node_store.get(node_name)
            assert len(datas) > 0, '{} has no data??'.format(node_name)
            zmq_send_to_process(zmq_idle_clients, zmq_skt, [b'pnts', node_name, datas])
            node_store.remove(node_name)
            state.to_pnts.active.append(node_name)


        if can_queue_more_jobs(zmq_idle_clients):
            potential = sorted(
                [(k, v) for k, v in state.node_process.input.items() if k not in state.node_process.active],
                key=lambda f: -len(f[0]))

            while can_queue_more_jobs(zmq_idle_clients) and potential:
                target_count = 100000
                job_list = []
                count = 0
                idx = len(potential) - 1
                while count < target_count and potential and idx >= 0:
                    name, (tasks, point_count) = potential[idx]
                    if name not in state.node_process.active:
                        count += point_count
                        job_list += [name]
                        job_list += [node_store.get(name)]
                        job_list += [struct.pack('>I', len(tasks))]
                        job_list += tasks
                        del potential[idx]
                        del state.node_process.input[name]
                        state.node_process.active[name] = (len(tasks), point_count, now)

                        if name in state.node_process.inactive:
                            state.node_process.inactive.pop(state.node_process.inactive.index(name))
                    idx -= 1

                if job_list:
                    zmq_send_to_process(zmq_idle_clients, zmq_skt, job_list)

        while (state.las_reader.input and
           (points_in_progress < 60000000 or not state.las_reader.active) and
           len(state.las_reader.active) < max_splitting_jobs_count and
           can_queue_more_jobs(zmq_idle_clients)):
            if args.verbose >= 1:
                print('Submit next portion {}'.format(state.las_reader.input[-1]))
            _id = 'root_{}'.format(len(state.las_reader.input)).encode('ascii')
            file, portion = state.las_reader.input.pop()
            points_in_progress += portion[1] - portion[0]

            zmq_send_to_process(zmq_idle_clients, zmq_skt, [pickle.dumps({
                'filename': file,
                'offset_scale': (-avg_min, root_scale, rotation_matrix[:3,:3].T if rotation_matrix is not None else None, infos['color_scale']),
                'portion': portion,
                'id': _id
                })])

            state.las_reader.active.append(_id)

        # if at this point we have no work in progress => we're done
        if len(zmq_idle_clients) == args.jobs or zmq_processes_killed == args.jobs:
            if zmq_processes_killed < 0:
                zmq_send_to_all_process(zmq_idle_clients, zmq_skt, [pickle.dumps(b'shutdown')])
                zmq_processes_killed = 0
            else:
                assert points_in_pnts == infos['point_count'], '!!! Invalid point count in the written .pnts (expected: {}, was: {})'.format(
                        infos['point_count'], points_in_pnts)
                if args.verbose >= 1:
                    print('Writing 3dtiles {}'.format(infos['avg_min']))
                write_tileset(working_dir,
                              folder,
                              octree_metadata,
                              avg_min,
                              root_scale,
                              projection,
                              rotation_matrix,
                              args.rgb)
                shutil.rmtree(working_dir)
                if args.verbose >= 1:
                    print('Done')

                if args.benchmark is not None:
                    print('{},{},{},{}'.format(
                        args.benchmark,
                        ','.join([os.path.basename(f) for f in args.files]),
                        points_in_pnts,
                        round(time.time() - startup, 1)))

                for p in zmq_processes:
                    p.terminate()
                break

        if at_least_one_job_ended:
            if args.verbose >= 3:
                print('{:^16}|{:^8}|{:^8}'.format('Name', 'Points', 'Seconds'))
                for name, v in state.node_process.active.items():
                    print('{:^16}|{:^8}|{:^8}'.format(
                        '{} ({})'.format(name.decode('ascii'), v[0]),
                        v[1],
                        round(now - v[2], 1)))
                print('')
                print('Pending:')
                print('  - root: {} / {}'.format(
                    len(state.las_reader.input),
                    initial_portion_count))
                print('  - other: {} files for {} nodes'.format(
                    sum([len(f[0]) for f in state.node_process.input.values()]),
                    len(state.node_process.input)))
                print('')
            elif args.verbose >= 2:
                state.print_debug()
            if args.verbose >= 1:
                print('{} % points in {} sec [{} tasks, {} nodes, {} wip]'.format(
                    round(100 * processed_points / infos['point_count'], 2),
                    round(now, 1),
                    args.jobs - len(zmq_idle_clients),
                    len(state.node_process.active),
                    points_in_progress))
            elif args.verbose >= 0:
                percent = round(100 * processed_points / infos['point_count'], 2)
                time_left = (100 - percent) * now / (percent + 0.001)
                print('\r{:>6} % in {} sec [est. time left: {} sec]'.format(percent, round(now), round(time_left)), end='', flush=True)
                if False and int(percent) != previous_percent:
                    print('')
                    previous_percent = int(percent)

            if args.graph:
                percent = round(100 * processed_points / infos['point_count'], 3)
                print('{}, {}'.format(time.time() - startup, percent), file=progression_log)

        node_store.control_memory_usage(args.cache_size, args.verbose)

    if args.verbose >= 1:
        print('destroy', round(time_waiting_an_idle_process, 2))

    if args.graph:
        progression_log.close()

    # pygal chart
    if args.graph:
        import pygal
        from datetime import timedelta

        dateline = pygal.XY(x_label_rotation=25, secondary_range=(0, 100)) #, show_y_guides=False)
        for pid in activities:
            activity = []
            filename = 'activity.{}.csv'.format(pid)
            i = len(activities) - activities.index(pid) - 1
            # activities.index(pid) =
            with open(filename, 'r') as f:
                content = f.read().split('\n')
                for line in content[1:]:
                    line = line.split(',')
                    if line[0]:
                        ts = float(line[0])
                        value = int(line[1]) / 3.0
                        activity.append((ts, i + value * 0.9))

            os.remove(filename)
            if activity:
                activity.append((activity[-1][0], activity[0][1]))
                activity.append(activity[0])
                dateline.add(str(pid), activity, show_dots=False, fill=True)

        with open('progression.csv', 'r') as f:
            values = []
            for line in f.read().split('\n'):
                if line:
                    line = line.split(',')
                    values += [(float(line[0]), float(line[1]))]
        os.remove('progression.csv')
        dateline.add('progression', values, show_dots=False, secondary=True, stroke_style={'width':2, 'color': 'black'})


        dateline.render_to_file('activity.svg')

    context.destroy()

if __name__ == '__main__':
    main()

