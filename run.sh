#!/bin/bash -ex
# change mandatory
SYNAPSE_SERVER_NAME=my.matrix.host
SYNAPSE_HOST_PORT_HTTP=8008
SYNAPSE_UID=991
SYNAPSE_GID=991

SYNAPSE_VOLUME_HOST_PATH=/volume2/docker/synapse/app/data
POSTGRES_VOLUME_HOST_PATH=/volume2/docker/synapse/db/data

# change optional
SYNAPSE_MAX_UPLOAD_SIDE=64M
SYNAPSE_ENABLE_REGISTRATION=true

POSTGRES_HOST=db
POSTGRES_DB=synapse
POSTGRES_USER=synapse
POSTGRES_PASSWORD=synapse

# change if you know what you're doing
SYNAPSE_IMAGE=matrixdotorg/synapse:latest
SYNAPSE_REPORT_STATS=no
SYNAPSE_TZ=Europe/Berlin
SYNAPSE_NO_TLS=true
SYNAPSE_DATA_DIR=/data
SYNAPSE_CONFIG_DIR=/data
SYNAPSE_CONFIG_PATH=${SYNAPSE_CONFIG_DIR}/homeserver.yaml
SYNAPSE_WORKER=synapse.app.homeserver

POSTGRES_IMAGE=postgres:13.1-alpine
POSTGRES_INITDB_ARGS="--encoding=UTF-8 --lc-collate=C --lc-ctype=C"

# project name, will be prefix to *_SERVICE_NAME in container names
DOCKER_COMPOSE_PROJECT=matrix

create_volume_host_path(){
    
    for path in "${SYNAPSE_VOLUME_HOST_PATH}" "${POSTGRES_VOLUME_HOST_PATH}"; do
        if [ ! -e "${SYNAPSE_VOLUME_HOST_PATH}" ];then
            mkdir -p "${path}"
        fi
    done
}


create_log_config(){
    if [ ! -e "${SYNAPSE_VOLUME_HOST_PATH}/${SYNAPSE_SERVER_NAME}.log.config" ];then
        cp $( dirname "$0" )/log.template "${SYNAPSE_VOLUME_HOST_PATH}/${SYNAPSE_SERVER_NAME}.log.config"
    fi
}

create_homeserver_yaml(){
    if [ ! -e "${SYNAPSE_VOLUME_HOST_PATH}/homeserver.yaml" ];then
        docker run -it --rm \
            -e SYNAPSE_SERVER_NAME=${SYNAPSE_SERVER_NAME} \
            -e SYNAPSE_REPORT_STATS=${SYNAPSE_REPORT_STATS} \
            -e SYNAPSE_CONFIG_DIR=${SYNAPSE_CONFIG_DIR} \
            -e SYNAPSE_CONFIG_PATH=${SYNAPSE_CONFIG_PATH} \
            -e SYNAPSE_DATA_DIR=${SYNAPSE_DATA_DIR} \
            -e UID=${SYNAPSE_UID} \
            -e GID=${SYNAPSE_GID} \
            -v "${SYNAPSE_VOLUME_HOST_PATH}:${SYNAPSE_CONFIG_DIR}:rw" \
            ${SYNAPSE_IMAGE} generate
    fi
}

render_homeserver_yaml(){
    opwd="$PWD"
    cd $( dirname "$0" )
    if [ ! -e "${SYNAPSE_VOLUME_HOST_PATH}/homeserver.yaml.bak" ]; then
        mv "${SYNAPSE_VOLUME_HOST_PATH}/homeserver.yaml" "${SYNAPSE_VOLUME_HOST_PATH}/homeserver.yaml.bak"
    fi 
    homeserver=$( grep -vE '(^#|\s#|^$)' "${SYNAPSE_VOLUME_HOST_PATH}/homeserver.yaml.bak")
    SYNAPSE_MACAROON_SECRET_KEY=$(grep --perl-regexp --only-matching '(?<=^macaroon_secret_key: ").*(?="$)' <<< "${homeserver}" )
    SYNAPE_REGISTRATION_SHARED_SECRET=$(grep --perl-regexp --only-matching '(?<=^registration_shared_secret: ").*(?="$)' <<< "${homeserver}" )
    SYNAPSE_FROM_SECRET=$(grep --perl-regexp --only-matching '(?<=^form_secret: ").*(?="$)' <<< "${homeserver}" )
    eval "echo \"$(<homeserver.yaml.template)\"" > "${SYNAPSE_VOLUME_HOST_PATH}/homeserver.yaml"

    cd "${opwd}"
}

chown_synapse_volume_host_path(){
    chown ${SYNAPSE_UID}:${SYNAPSE_GID} -R "${SYNAPSE_VOLUME_HOST_PATH}"
}

render_compose_file_and_execute(){
    # render variables into template file to create final docker-compose.yml
    opwd="$PWD"
    cd $( dirname "$0" )
    eval "echo \"$(<docker-compose.template)\"" | docker-compose --project-name "${DOCKER_COMPOSE_PROJECT}" --file  - $@ 
    cd "${opwd}"
}

create_nginx_reverse_proxy_config(){
    # identify letsencryp certificate path
    if [ -e /etc/nginx/appd.d/server.synapse.conf ];then
        for current_domain_cert in /usr/syno/etc/certificate/_archive/*; do
            if [ -d ${current_domain_cert} ] && [ -f ${current_domain_cert}/cert.pem ]; then
                openssl x509 -in ${current_domain_cert}/cert.pem -text | grep DNS:${HOSTNAME} > /dev/null 2>&1
                domain_found=$?
                if [ "${domain_found}" = "0" ]; then
                    SYNAPSE_NGINX_PRIVKEY=${current_domain_cert}/privkey.pem
                    SYNAPSE_NGINX_FULLCHAIN=${current_domain_cert}/fullchain.pem
                fi
            fi
        done
        eval "echo \"$(<nginx-synapse.conf.template)\"" > /etc/nginx/appd.d/server.synapse.conf
        #nginx -s reload
    fi
}

if [ -z "$1" ];then
    echo "provide param: prepare, fix or any docker-compose parameter"
    exit 1
fi
set -u
case "$1" in

    prepare)    create_volume_host_path
                create_log_config
                create_homeserver_yaml
                render_homeserver_yaml
                create_nginx_reverse_proxy_config
                chown_synapse_volume_host_path
                ;;

    fixperms)   chown_synapse_volume_host_path
                ;;

    *)          render_compose_file_and_execute
                ;;

esac
