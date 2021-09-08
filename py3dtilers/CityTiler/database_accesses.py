"""
Functions used to open the database.
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
        except FileNotFoundError:
            print('ERROR: ', sys.exec_info()[0])
            db_config_file.close()
            sys.exit()

    # Check that db configuration is well defined
    if (("PG_HOST" not in db_config) or ("PG_USER" not in db_config) or ("PG_NAME" not in db_config) or ("PG_PORT" not in db_config) or ("PG_PASSWORD" not in db_config)):
        print(("ERROR: Database is not properly defined in '{0}', please refer to README.md"
               .format(db_config_file_path)))
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
        # Refer to note standing after this fuction call on why those
        # keepalives parameters are here required.
        keepalives=1,
        keepalives_idle=30,
        keepalives_interval=10,
        keepalives_count=5
    )
    # Why using the keepalives flags in the above psycopg2 constructor ?
    # In the context of having to tile cities, such a connection can be
    # used for bulk querries (think of retrieving the geometries of all the
    # buildings of a large city). And it seems that dealing with bulk
    # querries in a dockerized context tends to (randomly) produce the
    # following error:
    #    psycopg2.OperationalError: server closed the connection unexpectedly
    #    This probably means the server terminated abnormally
    #    before or while processing the request.
    # For documented reports on this refer to
    #   - https://stackoverflow.com/questions/55457069/how-to-fix-operationalerror-psycopg2-operationalerror-server-closed-the-conn
    #   - https://stackoverflow.com/questions/53188306/python-sqlalchemy-connection-pattern-disconnected-from-the-remote-server
    # The keepalives solution is provided by this StackOverflow:
    # https://stackoverflow.com/questions/56289874/postgres-closes-connection-during-query-after-a-few-hundred-seconds-when-using-p
    #
    # Concerning the keepalives connect parameters, refer to
    # https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-PARAMKEYWORDS

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
