import sys
import os
import logging
import math
from py3dtiles import TilesetReader
from .tileset_tree import TilesetTree
from .TilesetMerger import TilesetMerger
from ..Common import Tiler, FromGeometryTreeToTileset
from .tile_to_feature import TileToFeatureList
import numpy as np
class TilesetTiler(Tiler):

    def __init__(self):
        super().__init__()
        self.tileset_of_root_tiles = list()
        self.reader = TilesetReader()

    def parse_command_line(self):
        super().parse_command_line()

        if len(self.args.paths) < 1:
            print("Please provide a path to directory containing the root of your 3DTiles.")
            print("Exiting")
            sys.exit(1)

    def retrieve_files(self, paths):
        """
        Retrieve the files from paths given by the user.
        :param paths: a list of paths
        """
        self.files = []

        for path in paths:
            if os.path.isdir(path):
                self.files.append(path)

        if len(self.files) == 0:
            print("No tileset was found")
            sys.exit(1)
        else:
            print(len(self.files), "tilesets found")

    def get_output_dir(self):
        """
        Return the directory name for the tileset.
        """
        if self.args.output_dir is None:
            return "tileset_reader_output"
        else:
            return self.args.output_dir

    def create_tileset_from_feature_list(self, tileset_tree, extension_name=None):
        """
        Override the parent tileset creation.
        """
        self.create_output_directory()
        return FromGeometryTreeToTileset.convert_to_tileset(tileset_tree, self.args, extension_name, self.get_output_dir())

    def transform_tileset(self, tileset):
        """
        Creates a TilesetTree where each node has FeatureList.
        Then, apply transformations (reprojection, translation, etc) on the FeatureList.
        :param tileset: the TileSet to transform

        :return: a TileSet
        """
        geometric_errors = self.args.geometric_error if hasattr(self.args, 'geometric_error') else [None, None, None]
        tileset_tree = TilesetTree(tileset, self.tileset_of_root_tiles, geometric_errors)
        return self.create_tileset_from_feature_list(tileset_tree)

    def read_and_merge_tilesets(self):
        """
        Read all tilesets and merge them into a single TileSet instance with the TilesetMerger.
        The paths of all tilesets are keeped to be able to find the source of each tile.
        :param paths_to_tilesets: the paths of the tilesets

        :return: a TileSet
        """
        tilesets = self.reader.read_tilesets(self.files)
        for tileset in tilesets :
            logging.warning("Reading " + tileset.path)
            root_tile = tileset.get_root_tile()
            nb_feature_tileset = 0
            nb_triangle_tileset = 0
            mean_attribute_batch_table_tileset = 0
            min_dist_tileset = math.inf
            max_dist_tileset = 0
            max_area_tileset = 0
            min_area_tileset = math.inf
            if 'children' in root_tile.attributes:
                for tile in root_tile.attributes['children']:
                    logging.warning("Reading " + tile.uri)
                    featureList = TileToFeatureList(tile)

                    nb_feature_tile = len(featureList.features)
                    nb_triangle_tile = 0
                    mean_attribute_batch_table_tile = 0
                    min_dist_tile = math.inf
                    max_dist_tile = 0
                    max_area_tile = 0
                    min_area_tile = math.inf
                    area_feature = []
                    for feature in featureList:
                        min_dist_feature = math.inf
                        max_dist_feature = 0
                        max_area_feature = 0
                        min_area_feature = math.inf
                        min_x = math.inf
                        max_x = -math.inf
                        min_y = math.inf
                        max_y = -math.inf
                        for triangle in feature.geom.triangles[0]:
                            norm_p0_p1 = np.linalg.norm(triangle[1]-triangle[0])
                            norm_p0_p2 = np.linalg.norm(triangle[2]-triangle[0])
                            norm_p1_p2 = np.linalg.norm(triangle[1]-triangle[2])
                            area = (norm_p0_p1)*(norm_p0_p2)/2
                            max_dist_feature = max(norm_p0_p1,norm_p0_p2,norm_p1_p2,max_dist_feature)
                            min_dist_feature = min(norm_p0_p1,norm_p0_p2,norm_p1_p2,min_dist_feature)
                            max_area_feature = max(area,max_area_feature)
                            min_area_feature = min(area,min_area_feature)
                            min_x = min(min_x,triangle[0][0],triangle[1][0],triangle[2][0])
                            max_x = max(max_x,triangle[0][0],triangle[1][0],triangle[2][0])
                            min_y = min(min_y,triangle[0][1],triangle[1][1],triangle[2][1])
                            max_y = max(max_y,triangle[0][1],triangle[1][1],triangle[2][1])
                        
                        
                        area_feature.append((max_x-min_x)*(max_y-min_y))
                        mean_attribute_batch_table_tile += len(feature.batchtable_data)
                        logging.info("Reading Feature batchtable id : " + str(feature.id) + " Nb triangle in feature: " + str(len(feature.geom.triangles[0])) + " Nb attribute: " + str(len(feature.batchtable_data)))
                        logging.info("Area : " + str((max_x-min_x)*(max_y-min_y)))
                        if(feature.batchtable_data["id"]):
                            logging.info("Feature id : " + str(feature.batchtable_data["id"]) + "distance : " + str(max_dist_feature) + " "+ str(min_dist_feature) + " area : " + str(max_area_feature) + " " + str(min_area_feature))
                        # if(feature.batchtable_data["gml_id"]):
                        #     logging.info("gmlid: " + str(feature.batchtable_data["gml_id"]))
                        max_dist_tile = max(max_dist_tile,max_dist_feature)
                        if(min_dist_feature != 0.0): min_dist_tile = min(min_dist_tile,min_dist_feature)
                        max_area_tile = max(max_area_tile,max_area_feature)
                        if(min_area_tile != 0.0): min_area_tile = min(min_area_tile,min_area_feature)
                        nb_triangle_tile +=  len(feature.geom.triangles[0])   


                    mean_attribute_batch_table_tile /= nb_feature_tile
                    logging.info("Nb feature in tile : " + str(nb_feature_tile))
                    logging.info("Mean area : " + str(np.mean(np.array(area_feature))))

                    logging.info("Nb triangle in tile : " + str(nb_triangle_tile))
                    logging.info("Mean attribute batch table in tile : " + str(mean_attribute_batch_table_tile))
                    logging.info("Dist : " + str(max_dist_tile) + " "+ str(min_dist_tile) + " Aire : " + str(max_area_tile) + " " + str(min_area_tile))
                    nb_feature_tileset += nb_feature_tile
                    nb_triangle_tileset += nb_triangle_tile
                    mean_attribute_batch_table_tileset += mean_attribute_batch_table_tile

                    max_dist_tileset = max(max_dist_tile,max_dist_tileset)
                    min_dist_tileset = min(min_dist_tile,min_dist_tileset)
                    max_area_tileset = max(max_area_tile,max_area_tileset)
                    min_area_tileset = min(min_area_tile,min_area_tileset)
                       
                mean_attribute_batch_table_tileset /= len(root_tile.attributes['children'])
                logging.info("Nb feature in tileset : " + str(nb_feature_tileset))
                logging.info("Nb triangle in tileset : " + str(nb_triangle_tileset))
                logging.info("Mean attribute in batch table in tileset : " + str(mean_attribute_batch_table_tileset)) 
                logging.info("Dist : " + str(max_dist_tileset) + " "+ str(min_dist_tileset) + " Aire : " + str(max_area_tileset) + " " + str(min_area_tileset))

                logging.info("*******************************************")       
        
        print("Tilesets reading finished")
        tileset, self.tileset_of_root_tiles = TilesetMerger.merge_tilesets(tilesets, self.files)
        return tileset


def main():
    logging.basicConfig(filename='tilesetreader.log', level=logging.INFO, filemode="w")
    logging.info('Started reading')

    tiler = TilesetTiler()
    tiler.parse_command_line()

    tileset = tiler.read_and_merge_tilesets()

    tileset = tiler.transform_tileset(tileset)
    tileset.write_as_json(tiler.get_output_dir())


if __name__ == '__main__':
    main()
