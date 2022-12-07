#!/usr/bin/env python3

import os
import sys
import json
import logging
import psycopg2
import psycopg2.extras
from psycopg2.extensions import AsIs
import time
import datetime


logging.basicConfig(
    format='%(asctime)s %(name)s %(levelname)s %(message)s',
    level=logging.DEBUG
)

conn = psycopg2.connect(
    host=os.getenv("PGHOST", "whoosh-db-stage-aurora.cluster-adsasdasdasdasdasd.us-east-1.rds.amazonaws.com"),
    port=os.getenv("PGPORT", 5432) ,
    database=os.getenv("PGDATABASE", "db-whoosh"),
    user='db-whoosh'
    password='asdasdasdasdasdasd',
    options="-c search_path=config-service"
)

FROM_ENV = "qa"
TO_ENV = "dev112"

CREATED_BY = "cs cloner"

logging.info("Cloning parameters from env \"%s\" to \"%s\"" % (FROM_ENV, TO_ENV))

cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
#cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
cur.execute("SELECT * FROM config WHERE environment='%s' AND application_name LIKE 'whoosh-%%'" % FROM_ENV)
#cur.execute("SELECT * FROM config WHERE environment='qa' AND application_name='whoosh-webapp' AND name LIKE 'menu-items'")
#print(cur.fetchall())

configs_count = 0
parameters_count = 0
for row in cur:
    configs_count += 1
    logging.info("Config: id=%s application_name=%s environment=%s name=%s application_version=%s" % (row['id'], row['application_name'], row['environment'], row['name'], row['application_version']))

    src_config_id = row["id"]
    row.pop("id", None)
    row["environment"] = TO_ENV
    row["created"] = time.strftime("%Y-%m-%d %H:%M:%S", datetime.datetime.utcnow().timetuple())
    row["created_by"] = CREATED_BY
    row.pop("modified", None)
    row.pop("modified_by", None)
    columns = row.keys()
    values = tuple([row[column] for column in columns])
    #print(columns)
    #print(values)
    cur2 = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)    
    query = cur2.mogrify(
        'INSERT INTO config (%s) VALUES %s RETURNING id', 
        (AsIs(','.join(columns)), tuple(values))
    )
    #print(query)
    cur2.execute(query)
    #conn.commit()
    
    new_config_id = cur2.fetchone()["id"]
    logging.info("Cloned config ID: %d" % new_config_id)

    query = "INSERT INTO parameter \
            (config_id, name, description, payload, created, created_by, revision, env_specific) \
            SELECT '%d', name, description, payload, now(), '%s', revision, env_specific \
            FROM parameter \
            WHERE config_id = %d \
            RETURNING *" % (new_config_id, CREATED_BY, src_config_id)
    #print(query)
    cur2.execute(query)
    #conn.commit()

    for p_row in cur2:
        parameters_count += 1
        #logging.debug("Cloned parameters: \t%d %s %s = %s" % (p_row["id"], row["name"], p_row["name"], json.dumps(p_row["payload"])))
        logging.info("Cloned parameter: id=%d name=%s" % (p_row["id"], p_row["name"]))

conn.commit()

logging.info("SUMMARY: Cloned %d configs, %d parameters" % (configs_count, parameters_count))

#if __name__ == '__main__':
#    sys.exit(main())
