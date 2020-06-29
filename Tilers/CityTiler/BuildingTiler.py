import argparse
import numpy as np
import pywavefront 

from os import listdir
from os.path import isfile, join

from py3dtiles import B3dm, BatchTable, BoundingVolumeBox, GlTF
from py3dtiles import Tile, TileSet

from kd_tree import kd_tree
from citym_cityobject import CityMCityObjects
from citym_building import CityMBuildings
from citym_relief import CityMReliefs
from citym_waterbody import CityMWaterBodies
from database_accesses import open_data_base
from database_accesses_batch_table_hierarchy import create_batch_table_hierarchy
from obj import Obj

def parse_command_line():
    # arg parse
    text = '''A small utility that build a 3DTiles tileset out of the content
               of an obj repository extracted from FME'''
    parser = argparse.ArgumentParser(description=text)

    # adding positional arguments
    parser.add_argument('objs_path',
                        nargs='?',
                        default='CityTilerDBConfig.yml',
                        type=str,  # why precise this if it is the default config ?
                        help='path to the database configuration file')

    return parser.parse_args()



def create_tile_content(objects_with_id_key,pre_tile):
    #create B3DM content
    arrays = []
    for id in pre_tile:
        obj = objects_with_id_key[id]
        arrays.append({
            'position': obj.getPositionArray(),
            'normal': obj.getNormalArray(),
            'bbox': [[float(i) for i in j] for j in obj.getBbox()]
        })
    
    # transform = np.array([1, 0,  0, 0,
    #                   0, 0, -1, 0,
    #                   0, 1,  0, 0,
    #                   0, 0,  0, 1])
    
    transform = np.array([1, 0,  0, 0,
                       0, 1, 0, 0,
                       0, 0,  1, 0,
                       0, 0,  0, 1])
    
    gltf = GlTF.from_binary_arrays(arrays, transform)
    
    bt = BatchTable()
    bt.add_property_from_array("ifc.id", pre_tile)

    # bth = create_batch_table_hierarchy(ids)
    # bt.add_extension(bth)

    return B3dm.from_glTF(gltf, bt)


def from_objs_directory(path):    
    
    objects_with_ifc_key = dict()
        
    obj_rep = listdir(path)
    for obj_file in obj_rep:
        id = obj_file.replace('.obj','')

        obj = Obj(id)
        obj.parse_geom(pywavefront.Wavefront(path + "/" + obj_file, collect_faces = True))
        objects_with_ifc_key[id] = obj 
        break
    
    #kd_tree avec tile par id 
         
         
    tileset = TileSet()
    tile = Tile()  
    tile.set_geometric_error(500)

    tile_content_b3dm = create_tile_content(objects_with_ifc_key,tile)

    
    
    tile.set_content(tile_content_b3dm)
    return TileSet()


def main():
    """
    :return: no return value

    this function creates a repository name "junk_object_type" where the
    tileset is stored.
    """
    args = parse_command_line()
    
    mypath = args.objs_path
    ifc_rep = listdir(mypath)

    for ifc_class_rep in ifc_rep:

        tileset = from_objs_directory(mypath + ifc_class_rep)
        tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
        tileset.write_to_directory('junk_obj')
        break

    #tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())


if __name__ == '__main__':
    main()
