import os
import time
import gc
import lz4.frame as gzip
from sys import getsizeof
from py3dtiles.points.utils import name_to_filename


class SharedNodeStore:
    def __init__(self, folder):
        self.metadata = {}
        self.data = []
        self.folder = folder
        self.stats = {
            'hit': 0,
            'miss': 0,
            'new': 0,
        }
        self.memory_size = {
            'content': 0,
            'container': getsizeof(self.data) + getsizeof(self.metadata),
        }

    def control_memory_usage(self, max_size_MB, verbose):
        bytes_to_mb = 1.0 / (1024 * 1024)
        max_size_MB = max(max_size_MB, 200)

        if verbose >= 3:
            self.print_statistics()

        # guess cache size
        cache_size = (self.memory_size['container'] + self.memory_size['content']) * bytes_to_mb

        before = cache_size
        if before < max_size_MB:
            return

        if verbose >= 2:
            print('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CACHE CLEANING [{}]'.format(before))
        dropped = self.remove_oldest_nodes(1 - max_size_MB / before)
        gc.collect()

        if verbose >= 2:
            print('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< CACHE CLEANING')


    def get(self, name, stat_inc=1):
        metadata = self.metadata.get(name, None)
        data = b''
        if metadata is not None:
            data = self.data[metadata[1]]
            self.stats['hit'] += stat_inc
        else:
            filename = name_to_filename(self.folder, name)
            if os.path.exists(filename):
                self.stats['miss'] += stat_inc
                with open(filename, 'rb') as f:
                    data = f.read()
            else:
                self.stats['new'] += stat_inc
            # should we cache this node?

        return data

    def remove(self, name):
        meta = self.metadata.pop(name, None)

        filename = name_to_filename(self.folder, name)
        if meta is None:
            assert os.path.exists(filename), '{} should exist'.format(filename)
        else:
            self.memory_size['content'] -= getsizeof(meta)
            self.memory_size['content'] -= len(self.data[meta[1]])
            self.memory_size['container'] = getsizeof(self.data) + getsizeof(self.metadata)
            self.data[meta[1]] = None

        if os.path.exists(filename):
            os.remove(filename)

    def put(self, name, data):
        compressed_data = gzip.compress(data)

        metadata = self.metadata.get(name, None)
        if metadata is None:
            metadata = (time.time(), len(self.data))
            self.data.append(compressed_data)
        else:
            metadata = (time.time(), metadata[1])
            self.data[metadata[1]] = compressed_data
        self.metadata.update([(name, metadata)])

        self.memory_size['content'] += len(compressed_data) + getsizeof((name, metadata))
        self.memory_size['container'] = getsizeof(self.data) + getsizeof(self.metadata)

    def remove_oldest_nodes(self, percent):
        count = _remove_all(self)

        self.memory_size['content'] = 0
        self.memory_size['container'] = getsizeof(self.data) + getsizeof(self.metadata)

        assert(len(self.metadata) == 0)
        assert(len(self.data) == 0)
        return count

    def print_statistics(self):
        print('Stats: Hits = {}, Miss = {}, New = {}'.format(
            self.stats['hit'],
            self.stats['miss'],
            self.stats['new']))

def _remove_all(store):
    # delete the entries
    count = len(store.metadata)
    bytes_written = 0
    for name, meta in store.metadata.items():
        data = store.data[meta[1]]
        filename = name_to_filename(store.folder, name)
        with open(filename, 'wb') as f:
            bytes_written += f.write(data)

    store.metadata = {}
    store.data = []

    return (count, bytes_written)
