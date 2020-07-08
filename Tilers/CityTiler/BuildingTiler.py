import argparse
import numpy as np
import pywavefront 

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
                        default='CityTilerDBConfig.yml',
                        type=str,  # why precise this if it is the default config ?
                        help='path to the database configuration file')

    return parser.parse_args()



def create_tile_content(pre_tile):
    #create B3DM content
    ids = [obj.get_id() for obj in pre_tile]

    arrays = []
    for obj in pre_tile:
        arrays.append({
            'position': obj.getPositionArray(),
            'normal': obj.getNormalArray(),
            'bbox': [[float(i) for i in j] for j in obj.getBbox()]
        })
    
    transform = np.array([1, 0,  0, 0,
                      0, 0, -1, 0,
                      0, 1,  0, 0,
                      0, 0,  0, 1])
    
    # transform = np.array([1, 0,  0, 0,
                    #    0, 1, 0, 0,
                    #    0, 0,  1, 0,
                    #    0, 0,  0, 1])
    
    gltf = GlTF.from_binary_arrays(arrays, transform)
    
    
    
    bt = BatchTable()
    bt.add_property_from_array("ifc.id", ids)

    # bth = create_batch_table_hierarchy(ids)
    # bt.add_extension(bth)

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

# def translate_tileset(objects,centroid_tileset):
#     for obj in objects:
#         for triangle in obj.get_geom():
#             for points in triangle:
#                 points -= centroid_tileset
#         obj.set_bbox()

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




def from_objs_directory(path):    
    
    objects = []
        
    obj_rep = listdir(path)
    print(str(len(obj_rep)) + " .obj to parse")
    for obj_file in obj_rep:
        id = obj_file.replace('.obj','')
        obj = Obj(id)
        if(obj.parse_geom(path + "/" + obj_file)):
            objects.append(obj)

    if(len(objects) == 0):
        return None

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
                    centroid_tileset[0], centroid_tileset[1], centroid_tileset[2] + 310, 1])
        bounding_box = BoundingVolumeBox()
        
        for obj in pre_tile:
            bounding_box.add(obj.get_bounding_volume_box()) 
        tile.set_bounding_volume(bounding_box)
        tileset.add_tile(tile)


    return tileset


def main():
    """
    :return: no return value

    this function creates a repository name "junk_object_type" where the
    tileset is stored.
    """
    args = parse_command_line()
    
    mypath = args.objs_path
    ifc_rep = listdir(mypath)
    ifc_classes = ""
    for ifc_class_rep in ifc_rep:
        print("Writing " + ifc_class_rep )
        tileset = from_objs_directory(mypath + ifc_class_rep)
        if(tileset != None):
            tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())
            tileset.write_to_directory("ifc_tilesets/"+ifc_class_rep)
            ifc_classes+= ifc_class_rep + ";"

    f = open("ifc_tilesets/classes.txt","w")
    f.write(ifc_classes)
    f.close()    

    #tileset.get_root_tile().set_bounding_volume(BoundingVolumeBox())


if __name__ == '__main__':
    main()
