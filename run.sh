#!/bin/bash -e
source $( dirname "$0" )/config

create_volume_host_path(){
    for path in "${SYNAPSE_VOLUME_HOST_PATH}" "${ELEMENT_VOLUME_HOST_PATH}" "${POSTGRES_VOLUME_HOST_PATH}"; do
        if [ "$path" == "${ELEMENT_VOLUME_HOST_PATH}" ];then
            if [ "${ELEMENT_ENABLED}" = "yes" ] && [ ! -e "${path}" ];then
                echo "creating host path for volume: ${path}"
                mkdir -p "${path}"
            fi
        else
            if [ ! -e "${path}" ] ;then
                echo "creating host path for volume: ${path}"
                mkdir -p "${path}"
            fi
        fi
    done
}

create_synapse_log_config(){
    if [ ! -e "${SYNAPSE_VOLUME_HOST_PATH}/${SYNAPSE_SERVER_NAME}.log.config" ];then
        echo "copying synapse log.conf"
        cp $( dirname "$0" )/log.template "${SYNAPSE_VOLUME_HOST_PATH}/${SYNAPSE_SERVER_NAME}.log.config"
    fi
}

create_synapse_homeserver_yaml(){
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

render_synapse_homeserver_yaml(){
    echo "rendering synapse homeserver.yaml"
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

chown_volume_host_paths(){
    for path in "${SYNAPSE_VOLUME_HOST_PATH}" "${ELEMENT_VOLUME_HOST_PATH}" "${POSTGRES_VOLUME_HOST_PATH}"; do
        if [ "$path" == "${ELEMENT_VOLUME_HOST_PATH}" ];then
            if [ "${ELEMENT_ENABLED}" = "yes" ];then
                echo "fixing permissions on ${path}"
                chown ${SYNAPSE_UID}:${SYNAPSE_GID} -R "${path}"
            fi
        else
            echo "fixing permissions on ${path}"
            chown ${SYNAPSE_UID}:${SYNAPSE_GID} -R "${path}"
        fi
    done
}

render_compose_file_and_execute(){
    # render variables into template file to create final docker-compose.yml
    opwd="$PWD"
    cd $( dirname "$0" )
    echo "rendering docker-compose.yml and passing it to docker-compose"
    eval "echo \"$(<docker-compose.template)\"" | docker-compose --project-name ${DOCKER_COMPOSE_PROJECT} --file - $@
    cd "${opwd}"
}

create_nginx_reverse_proxy_config(){
    opwd="$PWD"
    cd $( dirname "$0" )
    # identify letsencryp certificate path
    echo "rendering reverse proxy configuration"
    synapse_found=false
    element_found=false
    error=false

    SYNAPSE_REVERSE_PROXY_SERVER_NAME=$(grep --perl-regexp --only-matching '(?<=^https://).*(?=(:.*$))' <<< "${SYNAPSE_PUBLIC_BASEURL}")
    if [ "${ELEMENT_ENABLED}" = "yes" ];then
        ELEMENT_REVERSE_PROXY_SERVER_NAME=$(grep --perl-regexp --only-matching '(?<=^https://).*(?=(:.*$))' <<< "${ELEMENT_PUBLIC_BASEURL}")
    fi

    if [ "${ELEMENT_ENABLED}" = "yes" ] && [ "${SYNAPSE_REVERSE_PROXY_SERVER_NAME}" == "${ELEMENT_REVERSE_PROXY_SERVER_NAME}" ];then
        echo "synapse and element are not allowed to share the same domain, see: https://github.com/vector-im/element-web#important-security-note"
        error=true
    fi

    if [ "${error}" == "false" ];then
        for current_domain_cert in /usr/syno/etc/certificate/_archive/*; do
            if [ -d ${current_domain_cert} ] && [ -f ${current_domain_cert}/cert.pem ]; then
                cert_data=$(openssl x509 -in ${current_domain_cert}/cert.pem -text)
                if [ $(echo "${cert_data}" | grep -E "(CN=|DNS:)(${SYNAPSE_REVERSE_PROXY_SERVER_NAME}|\*\.${SYNAPSE_REVERSE_PROXY_SERVER_NAME#*.})" -wc) -gt 0 ];then
                    echo "synapse: matching certificate found for ${SYNAPSE_REVERSE_PROXY_SERVER_NAME}, rending reverse proxy config"
                    synapse_found=true
                    SYNAPSE_NGINX_PRIVKEY=${current_domain_cert}/privkey.pem
                    SYNAPSE_NGINX_FULLCHAIN=${current_domain_cert}/fullchain.pem
                    eval "echo \"$(<nginx-synapse.conf.template)\"" > /etc/nginx/conf.d/http.synapse.conf
                    reload=true
                fi
                if [ "${ELEMENT_ENABLED}" = "yes" ] && [ $(echo "${cert_data}" | grep -E "(CN=|DNS:)(${ELEMENT_REVERSE_PROXY_SERVER_NAME}|\*\.${ELEMENT_REVERSE_PROXY_SERVER_NAME#*.})" -wc) -gt 0 ];then
                    echo "synapse: matching certificate found for ${ELEMENT_REVERSE_PROXY_SERVER_NAME}, rending reverse proxy config"
                    element_found=true
                    ELEMENT_NGINX_PRIVKEY=${current_domain_cert}/privkey.pem
                    ELEMENT_NGINX_FULLCHAIN=${current_domain_cert}/fullchain.pem
                    eval "echo \"$(<nginx-element.conf.template)\"" > /etc/nginx/conf.d/http.element.conf
                    reload=true
                fi
            fi
        done
        if [ "${synapse_found}" == "true" ] || [ "${element_found}" == "true" ] ;then
            echo "reloading nginx config to activate reverse proxy configuration"
            nginx -s reload
        else
            if [ "${synapse_found}" == "false" ]; then
                echo "synapse: No matching certificate for found!"
                error=true
            fi
            if [ "${ELEMENT_ENABLED}" = "yes" ] && [ "${element_found}" == "false" ]; then
                echo "element: No matching certificate for found!"
                error=true
            fi
        fi
    fi
    cd "${opwd}"
    if [ "${error}" == "true" ];then
        exit 1
    fi
}

render_element_config_json(){
    if [ "${ELEMENT_ENABLED}" = "yes" ]; then
        echo "rendering element config.json"
        opwd="$PWD"
        cd $( dirname "$0" )
        eval "echo \"$(<element-web.conf.json.template)\"" > "${ELEMENT_VOLUME_HOST_PATH}/conf.json"
        cd "${opwd}"
    fi
}

if [ -z "$1" ];then
    echo "provide param: prepare, fixperms or any docker-compose parameter"
    exit 1
fi
set -u
case "$1" in

    prepare)    create_volume_host_path
                create_synapse_log_config
                create_synapse_homeserver_yaml
                render_synapse_homeserver_yaml
                render_element_config_json
                create_nginx_reverse_proxy_config
                chown_volume_host_paths
                ;;

    fixperms)   chown_volume_host_paths
                ;;

    *)          render_compose_file_and_execute $@
                ;;

esac
