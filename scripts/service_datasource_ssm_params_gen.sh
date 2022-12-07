#!/usr/bin/env bash

ENV="prod"
STAGES="iotsnapshots"
DB="replica"

CREDS="whoosh_service_iotsnapshots:22xfdhfdhfhdf78i0Ja"

for STAGE in ${STAGES}; do
    while read line; do
        echo "# Process: /service/api/${ENV}/${STAGE}/datasource/${DB}"
        user=$(echo ${line} | cut -d':' -f1)
        passwd=$(echo ${line} | cut -d':' -f2)

        #if [[ "whoosh_service_preprod_${STAGE}" != ${user} ]]; then
        #    echo "continue"
        #    continue
        #fi

        #        # Add SSM Param
        #        # WARNING!!! Reformat after uncommenting
        #        TEMPLATE="{
        #    \"database\": \"db-whoosh\",
        #    \"host\": \"whoosh-prod-aurora.cluster-ro-cqlssdfsdfsdfsdfvpdknncb.eu-west-1.rds.amazonaws.com\",
        #    \"jdbc_url\": \"jdbc:postgresql://whoosh-prod-aurora.cluster-ro-cqlssdfsdfsdfsdfvpdknncb.eu-west-1.rds.amazonaws.com:5432/db-whoosh\",
        #    \"password\": \"${passwd}\",
        #    \"port\": 5432,
        #    \"username\": \"${user}\"
        #}"
        aws ssm put-parameter --overwrite --name /service/api/${ENV}/${STAGE}/datasource/${DB} --value "${TEMPLATE}" --type SecureString

        # Add default privileges in PG
        export PGUSER=${user}
        export PGPASSWORD=${passwd}
        #for obj in TABLES SEQUENCES FUNCTIONS; do
        #    # psql -a -h whoosh-db-prod-aurora.cluster-cqlssdfsdfsdfsdfvpdknncb.eu-west-1.rds.amazonaws.com -c "..."
        #    psql -a -h whoosh-db-prod-aurora.cluster-cqlssdfsdfsdfsdfvpdknncb.eu-west-1.rds.amazonaws.com -c "alter default privileges for role ${user} in schema public grant all ON ${obj} to \"db-whoosh\";"
        #    psql -a -h whoosh-prod-aurora.cluster-cqlssdfsdfsdfsdfvpdknncb.eu-west-1.rds.amazonaws.com -c "alter default privileges for role ${user} in schema public grant all ON ${obj} to \"db-whoosh\";"
        #done

    done <<<${CREDS}
done
