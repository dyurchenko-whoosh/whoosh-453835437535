#!/usr/bin/env bash

#set -o errexit
set -o pipefail

if [[ "${WHOOSH_DEBUG}" ]]; then
    set -x
fi

export PATH="$(dirname $(realpath ${0})):${PATH}"

log() {
    printf "[$(date +"%Y-%m-%d %H:%M:%S %z")] \e[1;95m${*}\n\e[0m"
}

log_err() {
    printf "[$(date +"%Y-%m-%d %H:%M:%S %z")] \e[1;31mERROR: \e[1;95m${*}\n\e[0m" >&2
}

usage() {
    printf "Usage:"
    printf "  %s\n" "$(basename ${0}) --src-env ENV --dst-env ENV [--yes]"
    printf "\n"
    printf "Options:\n"
    printf "  %-25s %s\n" "--src-env" "Source environment"
    printf "  %-25s %s\n" "--dst-env" "Destination environment"
    printf "  %-25s %s\n" "--yes" "Autoconfirm"
    printf "  %-25s %s\n" "-h, --help" "Print help"
    printf "\n"
    printf "Environment variables:\n"
    printf "  %-25s %s\n" "SRC_ENV" "Source environment"
    printf "  %-25s %s\n" "DST_ENV" "Destination environment"
    printf "  %-25s %s\n" "YES" "Autoconfirm"
    printf "\n"
    printf "Example:\n"
    printf "  $(basename ${0}) \
--src-env stage \
--dst-env dev0 \
--yes"
    printf "\n"
    printf "\n"
    exit 1
}

# Process options
while [[ $# -gt 0 ]]; do
    case "${1}" in
        -h | --help)
            usage
            exit 1
            ;;
        --src-env)
            shift
            if [[ "${1}" == "--"* ]]; then
                log_err "Value not specified for parameter"
                exit 1
            fi
            SRC_ENV=${1}
            shift
            ;;
        --dst-env)
            shift
            if [[ "${1}" == "--"* ]]; then
                log_err "Value not specified for parameter"
                exit 1
            fi
            DST_ENV=${1}
            shift
            ;;
        --yes)
            YES="y"
            shift
            ;;
    esac
done

# Default parameters
CREATED_BY_COMMENT='devops cs clone script'
DB_SECRET_ID=${DB_SECRET_ID:-"/service/db/whoosh-db-stage-aurora/username/postgres"}

CS_PGHOST=${CS_PGHOST:-"whoosh-db-stage-aurora.cluster-asdasdasdasdasdasd.us-east-1.rds.amazonaws.com"}
CS_PGPORT=${CS_PGPORT:-5432}
CS_PGDATABASE=${SRC_PGDATABASE:-"db-whoosh"}
CS_PGSCHEMA=${CS_PGSCHEMA:-"config-service"}
CS_PGUSER="postgres"
CS_PGPASSWORD="qweqweqweqeasdasdasdasd"
CS_PGOPTIONS=${CS_PGOPTIONS:-"-c search_path=${CS_PGSCHEMA}"}

# For debug: CS_PGHOST="whoosh-db-test2.cluster-cnm8gsaqbmae.us-east-1.rds.amazonaws.com" CS_PGDATABASE="db-whoosh-dev0"

if [[ -z "${CS_PGUSER}" && -z "${CS_PGPASSWORD}" ]]; then
    log "Postgres database username and password not found in environment vars, try to get from AWS SecretsManager"
    while read line; do export ${line}; done < <(aws --region us-east-1 secretsmanager \
        get-secret-value \
        --secret-id ${DB_SECRET_ID} \
        --query SecretString --output text |
        jq -r 'to_entries|map(select(.key=="username" or .key=="password") | "CS_PG\(.key | ascii_upcase)=\(.value|tostring)")|.[]' |
        sed 's/CS_PGUSERNAME=/CS_PGUSER=/g')
    if [[ $? -ne 0 ]]; then
        log_err "Failed to get source database username and password from AWS SecretsManager"
        exit 1
    fi
fi

# Validate inputs
if [[ -z "${SRC_ENV}" ]]; then
    log_err "Source environment doesn't specified"
    usage
    exit 1
fi
if [[ -z "${DST_ENV}" ]]; then
    log_err "Destination environment doesn't specified"
    usage
    exit 1
fi
if [[ -z "${CS_PGHOST}" ]] || [[ -z "${CS_PGUSER}" ]] || [[ -z "${CS_PGPASSWORD}" ]] || [[ -z "${CS_PGDATABASE}" ]]; then
    log_err "Destination host, username or password doesn't specified"
    usage
    exit 1
fi

# Check valid clone directions
if [[ "${SRC_ENV}" == "${DST_ENV}" ]]; then
    log_err "Can't clone db to itself"
    exit 1
elif [[ "${SRC_ENV}" == 'prod' || "${DST_ENV}" == 'prod' ]]; then
    log "Cloning from or to \"prod\" environment is denied'"
    exit 1
elif [[ "${DST_ENV}" == 'stage' || "${DST_ENV}" == 'qa' ]]; then
    log "Cloning to \"stage\" environment is denied"
    exit 1

fi

log "Cloning configs and parameters from environment \"${SRC_ENV}\" to environment \"${DST_ENV}\""
log "ATTENTION: !!! Destination CS environment "${DST_ENV}" will be deleted with no backups !!!"

# Ask for confirmation
if [[ -z "${YES:=}" ]]; then
    read -p "Process? (y/n): " YES
    case "${YES}" in
        y | Y | YES | yes)
            :
            ;;
        *)
            log_err "Aborting"
            exit 1
            ;;
    esac
fi

# Process
start_time=$(date +"%s")

export PGHOST=${CS_PGHOST}
export PGPORT=${CS_PGPORT}
export PGDATABASE=${CS_PGDATABASE}
export PGUSER=${CS_PGUSER}
export PGPASSWORD=${CS_PGPASSWORD}
export PGOPTIONS=${CS_PGOPTIONS}

log "Clear \"${DST_ENV}\" environment old parameters"
cat <<EOF | psql -ab --set=ON_ERROR_STOP=1 --single-transaction
DO \$\$

END
\$\$;
EOF
if [[ $? -ne 0 ]]; then
    log_err "Failed to clear old parameters"
    exit 1
fi

log "Clone parameters from env \"${SRC_ENV}\" to env \"${DST_ENV}\""
cat <<EOF | psql -ab --set=ON_ERROR_STOP=1 --single-transaction
DO \$\$

END
\$\$;
EOF
if [[ $? -ne 0 ]]; then
    log_err "Failed to clone environment configs and parameters"
    exit 1
fi

#cat <<EOF | psql -ab --set=ON_ERROR_STOP=1 --single-transaction -t -A -F$'\t' -P pager=off | awk '{print "Cloned: " $1 " configs, " $2 " parameters"}'
CLONE_STATS=($(
    cat <<EOF | psql -ab --set=ON_ERROR_STOP=1 --single-transaction -t -A -F" " -P pager=off
SELECT
    COUNT(DISTINCT c.id) AS "configs_count",
    COUNT(*) AS "parameters_count"
FROM "parameter" p, config c
WHERE p.config_id = c.id AND c.environment = '${DST_ENV}'
EOF
))
log "Cloned: ${CLONE_STATS[0]} configs, ${CLONE_STATS[1]} parameters"
if [[ ${CLONE_STATS[0]} -eq 0 || ${CLONE_STATS[1]} -eq 0 ]]; then
    log_err "No configs or params cloned. Something is gone wrong. Aborting."
    exit 1
fi

log "Add new env \"${DST_ENV}\" to AMS app (CS GUI) parameters"
cat <<EOF | psql -ab --set=ON_ERROR_STOP=1 --single-transaction
DO \$\$

END
\$\$;
EOF
if [[ $? -ne 0 ]]; then
    log_err "Failed to add cloned environment to cs gui (ams)"
    exit 1
fi

log "Clone CS environment completed"
log "Cloning took $(($(date +"%s") - start_time)) seconds"
