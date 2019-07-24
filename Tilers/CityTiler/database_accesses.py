"""
Notes on the 3DCityDB database general structure

The data is organised in the following way in the database:

### for buildings
  - the building table contains the "abstract" building
    subdivisions (building, building part)
  - the thematic_surface table contains all the surface objects (wall,
    roof, floor), with links to the building object it belongs to
    and the geometric data in the surface_geometry table

### for reliefs
  - the relief_feature table contains the complex relief objects which are composed
    by individual components that can be of different types - TIN/raster etc.)
  - the relief_component table contains individual relief components
  - the relief_feat_to_rel_comp table establishes a link between individual components and
    their "parent" which is a more complex relief object

### for all objects
  - the cityobject table contains information about all the objects
  - the surface_geometry table contains the geometry of all objects

"""


import sys
import yaml
import psycopg2
import psycopg2.extras


def open_data_base(db_config_file_path):
    with open(db_config_file_path, 'r') as db_config_file:
        try:
            db_config = yaml.load(db_config_file, Loader=yaml.FullLoader)
            db_config_file.close()
        except:
            print('ERROR: ', sys.exec_info()[0])
            db_config_file.close()
            sys.exit()

    # Check that db configuration is well defined
    if (   ("PG_HOST" not in db_config)
        or ("PG_USER" not in db_config)
        or ("PG_NAME" not in db_config)
        or ("PG_PORT" not in db_config)
        or ("PG_PASSWORD" not in db_config)):
        print(("ERROR: Database is not properly defined in '{0}', please refer to README.md"
              .format(args.db_config_path)))
        sys.exit()

    # Connect to database
    db = psycopg2.connect(
        "postgresql://{0}:{1}@{2}:{3}/{4}"
        .format(db_config['PG_USER'],
                db_config['PG_PASSWORD'],
                db_config['PG_HOST'],
                db_config['PG_PORT'],
                db_config['PG_NAME']),
        # fetch method will return named tuples instead of regular tuples
        cursor_factory=psycopg2.extras.NamedTupleCursor,
    )

    try:
        # Open a cursor to perform database operations
        cursor = db.cursor()
        cursor.execute('SELECT 1')
    except psycopg2.OperationalError:
        print('ERROR: unable to connect to database')
        sys.exit()

    return cursor


def open_data_bases(db_config_file_paths):
    cursors = list()
    for file_path in db_config_file_paths:
        cursors.append(open_data_base(file_path))
    return cursors
