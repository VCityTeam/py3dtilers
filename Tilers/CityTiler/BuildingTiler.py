import argparse
import numpy as np
import pywavefront 
import sys

import os
from os import listdir
from os.path import isfile, join

from py3dtiles import B3dm, BatchTable, BoundingVolumeBox, GlTF
from py3dtiles import Tile, TileSet

from obj import Obj

def parse_command_line():
    # arg parse
    text = '''A small utility that build a 3DTiles tileset out of the content
               of an obj repository extracted from FME'''
    parser = argparse.ArgumentParser(description=text)

    # adding positional arguments
    parser.add_argument('objs_path',
                        nargs='?',
                        type=str,  # why precise this if it is the default config ?
                        help='path to the database configuration file')

    result = parser.parse_args()
    if(result.objs_path == None):
        print("Please provide a path to a directory containing some obj files or multiple directories")
        print("Exiting")
        sys.exit(1)

    return parser.parse_args()



def create_tile_content(pre_tile):
    #create B3DM content

    arrays = []
    for obj in pre_tile:
        arrays.append({
            'position': obj.getPositionArray(),
            'normal': obj.getNormalArray(),
            'bbox': [[float(i) for i in j] for j in obj.getBbox()]
        })
    
    # GlTF uses a y-up coordinate system whereas the geographical data (stored
    # in the 3DCityDB database) uses a z-up coordinate system convention. In
    # order to comply with Gltf we thus need to realize a z-up to y-up
    # coordinate transform for the data to respect the glTF convention. This
    # rotation gets "corrected" (taken care of) by the B3dm/gltf parser on the
    # client side when using (displaying) the data.
    # Refer to the note concerning the recommended data workflow
    #    https://github.com/AnalyticalGraphicsInc/3d-tiles/tree/master/specification#gltf-transforms
    # for more details on this matter.
    transform = np.array([1, 0,  0, 0,
                      0, 0, -1, 0,
                      0, 1,  0, 0,
                      0, 0,  0, 1])  
    gltf = GlTF.from_binary_arrays(arrays, transform)

    # Create a batch table and add the ID of each obj to it
    ids = [obj.get_id() for obj in pre_tile]
    bt = BatchTable()
    bt.add_property_from_array("ifc.id", ids)

    # Eventually wrap the geometries together with the optional
    # BatchTableHierarchy within a B3dm:
    return B3dm.from_glTF(gltf, bt)


def kd_tree(objs, maxNumobj, depth=0):
    # The module argument of 2 (in the next line) hard-wires the fact that
    # this kd_tree is in fact a 2D_tree.
    axis = depth % 2

    # Within the sorting criteria point[1] refers to the centroid of the
    # bounding boxes of the city objects. And thus, depending on the value of
    # axis, we alternatively sort on the X or Y coordinate of those centroids:
    sObjs = sorted(objs, key=lambda obj: obj.get_centroid()[axis])
    median = len(sObjs) // 2
    lObjs = sObjs[:median]
    rObjs = sObjs[median:]
    pre_tiles = []
    if len(lObjs) > maxNumobj:
        pre_tiles.extend(kd_tree(lObjs, maxNumobj, depth + 1))
        pre_tiles.extend(kd_tree(rObjs, maxNumobj, depth + 1))
    else:
        pre_tiles.append(lObjs)
        pre_tiles.append(rObjs)
    return pre_tiles

def get_centroid_tileset(objects):
    centroid_tileset = np.array([0.,0.,0.])
    for obj in objects:
        centroid_tileset += obj.get_centroid()

    centroid_tileset /= len(objects)

    return centroid_tileset        


def translate_tileset(objects,centroid_tileset):
    for obj in objects:
        new_geom = []
        for triangle in obj.get_geom():
            new_position = []
            for points in triangle:
                new_position.append(np.array(points - centroid_tileset, dtype=np.float32))
            new_geom.append(new_position)
        obj.set_geom(new_geom)
        obj.set_bbox()


def retrieve_objs(path):
    """
    :param path: a path to a directory

    :return: a list of Obj. 
    """

    objects = []
        
    obj_dir = listdir(path)

    for obj_file in obj_dir:
        if(os.path.isfile(os.path.join(path,obj_file))):
            if(".obj" in obj_file):
                #Get id from its name
                id = obj_file.replace('.obj','')
                obj = Obj(id)
                #Create geometry as expected from GLTF from an obj file
                if(obj.parse_geom(os.path.join(path,obj_file))):
                    objects.append(obj)
    return objects
        
def from_obj_directory(path):    
    """
    :param path: a path to a directory

    :return: a tileset. 
    """
    
    objects = retrieve_objs(path)

    if(len(objects) == 0):
        print("No .obj found in " + path)
        return None
    else:
        print(str(len(objects)) + " .obj parsed")
    

    # Lump out objects in pre_tiles based on a 2D-Tree technique:
    pre_tileset = kd_tree(objects,200)       

    centroid_tileset = get_centroid_tileset(objects)  
    translate_tileset(objects,centroid_tileset)       
    
    tileset = TileSet()

    for pre_tile in pre_tileset:
        tile = Tile()  
        tile.set_geometric_error(500)

        tile_content_b3dm = create_tile_content(pre_tile)
        tile.set_content(tile_content_b3dm)
        tile.set_transform([1, 0, 0, 0,
                    0, 1, 0, 0,
                    0, 0, 1, 0,
                    centroid_tileset[0], centroid_tileset[1], centroid_tileset[2] + 315, 1])
        bounding_box = BoundingVolumeBox()
        
        for obj in pre_tile:
            bounding_box.add(obj.get_bounding_volume_box()) 
        tile.set_bounding_volume(bounding_box)
        tileset.add_tile(tile)


    return tileset

def containDirectory(path):
    """
    :param path: a path to a directory
    :return: true if the given directory contains at least one directory 
    """
    list_el = listdir(path)
    for el in list_el:
        if os.path.isdir(os.path.join(path,el)):
            return True 
    return False

def main():
    """
    :return: no return value

    this function creates either :
    - a repository named "obj_tileset" where the
    tileset is stored if the directory does only contains obj files.
    - or a repository named "obj_tilesets" that contains all tilesets are stored,
    created from sub_directories 
    and a classes.txt that contains the name of all tilesets
    """
    args = parse_command_line()   
    mypath = args.objs_path

    if (containDirectory(mypath)):
        ifc_rep = listdir(mypath)
        ifc_classes = ""
        for ifc_class_rep in ifc_rep:
            dir_path = os.path.join(mypath,ifc_class_rep)
            if(os.path.isdir(dir_path)):
                print("Writing " + dir_path )
                tileset = from_obj_directory(dir_path)
                if(tileset != None):
                    tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
                    tileset.write_to_directory(os.path.join("obj_tilesets",ifc_class_rep))
                    ifc_classes += ifc_class_rep + ";"
        if(ifc_classes != ""):
            f = open("obj_tilesets/classes.txt","w+")
            f.write(ifc_classes)
            f.close()    
        else:
            print("Please provide a path to a directory containing some obj files or multiple directories")
    else:
        tileset = from_obj_directory(mypath)
        if(tileset != None):
            tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
            print("Writing tileset")
            tileset.write_to_directory("obj_tileset/")   
        else:
            print("Please provide a path to a directory containing some obj files or multiple directories")





if __name__ == '__main__':
    main()
