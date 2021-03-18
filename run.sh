#!/bin/bash -e
source $( dirname "$0" )/config

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

create_volume_host_path(){
    for path in "${SYNAPSE_VOLUME_HOST_PATH}" "${POSTGRES_VOLUME_HOST_PATH}" "${ELEMENT_VOLUME_HOST_PATH}" "${MAUTRIX_WHATSAPP_VOLUME_HOST_PATH}" ; do
        if [ "$path" == "${ELEMENT_VOLUME_HOST_PATH}" ];then
            if [ "${ELEMENT_ENABLED}" = "yes" ];then
                if [ ! -e "${path}" ];then
                    mkdir -p "${path}"
                    printf "[ ${GREEN}OK${NC} ] created host path for volume: ${path}\n"
                else
                    printf "[ ${GREEN}OK${NC} ] re-using host path for volume: ${path}\n"
                fi
            fi
        elif [ "$path" == "${MAUTRIX_WHATSAPP_VOLUME_HOST_PATH}" ];then
            if [ "${MAUTRIX_WHATSAPP_ENABLED}" = "yes" ];then
                if [ ! -e "${path}" ];then
                    mkdir -p "${path}"
                    printf "[ ${GREEN}OK${NC} ] created host path for volume: ${path}\n"
                else
                    printf "[ ${GREEN}OK${NC} ] re-using host path for volume: ${path}\n"
                fi
            fi
        else
            if [ ! -e "${path}" ] ;then
                mkdir -p "${path}"
                printf "[ ${GREEN}OK${NC} ] created host path for volume: ${path}\n"
            else
                printf "[ ${GREEN}OK${NC} ] re-using host path for volume: ${path}\n"
            fi
        fi
        
    done
}

create_synapse_log_config(){
    if [ ! -e "${SYNAPSE_VOLUME_HOST_PATH}/${SYNAPSE_SERVER_NAME}.log.config" ];then
        printf "[ ${GREEN}OK${NC} ] copying synapse log.conf\n"
        cp $( dirname "$0" )/log.template "${SYNAPSE_VOLUME_HOST_PATH}/${SYNAPSE_SERVER_NAME}.log.config"
    fi
}

create_synapse_homeserver_yaml(){
    if [ ! -e "${SYNAPSE_VOLUME_HOST_PATH}/homeserver.yaml" ];then
        printf "[ ${GREEN}OK${NC} ] running synapse container to generate the homseerver.yaml\n"
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
        printf "[ ${GREEN}OK${NC} ] generated homeserver.yaml\n"
		printf "[ ${GREEN}OK${NC} ] stopped synapse container for further configuration\n"
    else 
        printf "[ ${GREEN}OK${NC} ] re-using existing homeserver.yaml (delete \"${SYNAPSE_VOLUME_HOST_PATH}/homeserver.yaml and ${SYNAPSE_VOLUME_HOST_PATH}/homeserver.yaml.bak\" if you want a fresh start)\n"
    fi
}

render_mautrix_whatsapp_config_yaml(){
    if [ "${MAUTRIX_WHATSAPP_ENABLED}" = "yes" ];then
        if [ ! -e "${MAUTRIX_WHATSAPP_VOLUME_HOST_PATH}/registration.yaml" ];then
            printf "[ ${GREEN}OK${NC} ] rendering mautrix-whatsapp config.yaml\n"
            opwd="$PWD"
            cd $( dirname "$0" )
            SYNAPSE_REVERSE_PROXY_SERVER_NAME=$(grep --perl-regexp --only-matching '(?<=^https://).*(?=(:.*$))' <<< "${SYNAPSE_PUBLIC_BASEURL}")
            eval "echo \"$(<mautrix-whatsapp.config.yaml.template)\"" > "${MAUTRIX_WHATSAPP_VOLUME_HOST_PATH}/config.yaml"
            cd "${opwd}"
            printf "[ ${GREEN}OK${NC} ] running mautrix-whatsapp registration.yaml\n"
            docker run --rm -v "${MAUTRIX_WHATSAPP_VOLUME_HOST_PATH}:/data" "${MAUTRIX_WHATSAPP_IMAGE}"
        fi
    fi
}

render_synapse_homeserver_yaml(){
    printf "[ ${GREEN}OK${NC} ] rendering synapse homeserver.yaml\n"
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
    for path in "${SYNAPSE_VOLUME_HOST_PATH}" "${POSTGRES_VOLUME_HOST_PATH}" "${ELEMENT_VOLUME_HOST_PATH}" "${MAUTRIX_WHATSAPP_VOLUME_HOST_PATH}"; do
        if [ "$path" == "${ELEMENT_VOLUME_HOST_PATH}" ];then
            if [ "${ELEMENT_ENABLED}" = "yes" ];then
                printf "[ ${GREEN}OK${NC} ] fixing permissions on ${path}\n"
                chown ${SYNAPSE_UID}:${SYNAPSE_GID} -R "${path}"
            fi
        elif [ "$path" == "${MAUTRIX_WHATSAPP_VOLUME_HOST_PATH}" ];then
            if [ "${MAUTRIX_WHATSAPP_ENABLED}" = "yes" ];then
                printf "[ ${GREEN}OK${NC} ] fixing permissions on ${path}\n"
                chown ${SYNAPSE_UID}:${SYNAPSE_GID} -R "${path}"
            fi
        else
            printf "[ ${GREEN}OK${NC} ] fixing permissions on ${path}\n"
            chown ${SYNAPSE_UID}:${SYNAPSE_GID} -R "${path}"
        fi
    done
}

render_compose_file_and_execute(){
    # render variables into template file to create final docker-compose.yml
    opwd="$PWD"
    cd $( dirname "$0" )
    printf "[ ${GREEN}OK${NC} ] rendering docker-compose.yml and passing it to docker-compose\n"
    eval "echo \"$(<docker-compose.template)\"" | docker-compose --project-name ${DOCKER_COMPOSE_PROJECT} --file - $@
    cd "${opwd}"
}

write_compose(){

    opwd="$PWD"
    cd $( dirname "$0" )
    printf "[ ${GREEN}OK${NC} ] render and write docker-compose.yml\n"
    eval "echo \"$(<docker-compose.template)\"" > docker-compose.yml
	cd "${opwd}"
}

create_nginx_reverse_proxy_config(){
    opwd="$PWD"
    cd $( dirname "$0" )
    # identify letsencryp certificate path
    synapse_found=false
    element_found=false
    error=false

    SYNAPSE_REVERSE_PROXY_SERVER_NAME=$(grep --perl-regexp --only-matching '(?<=^https://).*(?=(:.*$))' <<< "${SYNAPSE_PUBLIC_BASEURL}")
    if [ "${ELEMENT_ENABLED}" = "yes" ];then
        ELEMENT_REVERSE_PROXY_SERVER_NAME=$(grep --perl-regexp --only-matching '(?<=^https://).*(?=(:.*$))' <<< "${ELEMENT_PUBLIC_BASEURL}")
    fi

    if [ "${ELEMENT_ENABLED}" = "yes" ] && [ "${SYNAPSE_REVERSE_PROXY_SERVER_NAME}" == "${ELEMENT_REVERSE_PROXY_SERVER_NAME}" ];then
        printf "[ ${RED}ERROR${NC} ] synapse and element are not allowed to share the same domain, see: https://github.com/vector-im/element-web#important-security-note. Fix the issue and run prepare again!\n"
        error=true
    fi

    if [ "${error}" == "false" ];then
        for current_domain_cert in /usr/syno/etc/certificate/_archive/*; do
            if [ -d ${current_domain_cert} ] && [ -f ${current_domain_cert}/cert.pem ]; then
                cert_data=$(openssl x509 -in ${current_domain_cert}/cert.pem -text)
                if [ $(echo "${cert_data}" | grep -E "(CN=|DNS:)(${SYNAPSE_REVERSE_PROXY_SERVER_NAME}|\*\.${SYNAPSE_REVERSE_PROXY_SERVER_NAME#*.})" -wc) -gt 0 ];then
                    printf "[ ${GREEN}OK${NC} ] synapse: matching certificate found for ${SYNAPSE_REVERSE_PROXY_SERVER_NAME}, rending reverse proxy config\n"
                    synapse_found=true
                    SYNAPSE_NGINX_PRIVKEY=${current_domain_cert}/privkey.pem
                    SYNAPSE_NGINX_FULLCHAIN=${current_domain_cert}/fullchain.pem
                    eval "echo \"$(<nginx-synapse.conf.template)\"" > /etc/nginx/conf.d/http.synapse.conf
                    reload=true
                fi
                if [ "${ELEMENT_ENABLED}" = "yes" ] && [ $(echo "${cert_data}" | grep -E "(CN=|DNS:)(${ELEMENT_REVERSE_PROXY_SERVER_NAME}|\*\.${ELEMENT_REVERSE_PROXY_SERVER_NAME#*.})" -wc) -gt 0 ];then
                    printf "[ ${GREEN}OK${NC} ] element: matching certificate found for ${ELEMENT_REVERSE_PROXY_SERVER_NAME}, rending reverse proxy config\n"
                    element_found=true
                    ELEMENT_NGINX_PRIVKEY=${current_domain_cert}/privkey.pem
                    ELEMENT_NGINX_FULLCHAIN=${current_domain_cert}/fullchain.pem
                    eval "echo \"$(<nginx-element.conf.template)\"" > /etc/nginx/conf.d/http.element.conf
                    reload=true
                fi
            fi
        done
        if [ "${synapse_found}" == "true" ] || [ "${element_found}" == "true" ] ;then
            printf "[ ${GREEN}OK${NC} ] reloading nginx config to activate reverse proxy configuration\n"
            nginx -s reload
        else
            if [ "${synapse_found}" == "false" ]; then
                printf "[ ${RED}ERROR${NC} ] synapse: No matching certificate for found!\n"
                error=true
            fi
            if [ "${ELEMENT_ENABLED}" = "yes" ] && [ "${element_found}" == "false" ]; then
                printf "[ ${RED}ERROR${NC} ] element: No matching certificate for found!\n"
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
        printf "[ ${GREEN}OK${NC} ] rendering element config.json\n"
        opwd="$PWD"
        cd $( dirname "$0" )
        eval "echo \"$(<element-web.conf.json.template)\"" > "${ELEMENT_VOLUME_HOST_PATH}/conf.json"
        cd "${opwd}"
    fi
}

function sanity_check() {
    if [ $(id -u) -ne 0 ];then
        printf "[ ${RED}ERROR${NC} ] this script needs to be run as root, preferebly using sudo!\n"
        exit 1
    fi
}

function clean(){
    for path in "${SYNAPSE_VOLUME_HOST_PATH}" "${POSTGRES_VOLUME_HOST_PATH}" "${ELEMENT_VOLUME_HOST_PATH}" "${MAUTRIX_WHATSAPP_VOLUME_HOST_PATH}"; do
        if [ "$path" == "${ELEMENT_VOLUME_HOST_PATH}" ];then
            if [ "${ELEMENT_ENABLED}" = "yes" ];then
                printf "[ ${GREEN}OK${NC} ] deleting ${path}\n"
                rm -rf "${path}"
            fi
        elif [ "$path" == "${MAUTRIX_WHATSAPP_VOLUME_HOST_PATH}" ];then
            if [ "${MAUTRIX_WHATSAPP_ENABLED}" = "yes" ];then
                printf "[ ${GREEN}OK${NC} ] deleting ${path}\n"
                rm -rf "${path}"
            fi
        else
            printf "[ ${GREEN}OK${NC} ] deleting ${path}\n"
            rm -rf "${path}"
        fi
    done
	restart_nginx=false
	if [ -e /etc/nginx/conf.d/http.element.conf ];then
        printf "[ ${GREEN}OK${NC} ] removing element reverse proxy configuration\n"
        rm /etc/nginx/conf.d/http.element.conf
	    restart_nginx=true
	fi
	if [ -e /etc/nginx/conf.d/http.synapse.conf ];then
        printf "[ ${GREEN}OK${NC} ] removing synergy reverse proxy configuration\n"
	    rm /etc/nginx/conf.d/http.synapse.conf
		restart_nginx=true
	fi
	if [ "${restart_nginx}" == "true" ];then
        printf "[ ${GREEN}OK${NC} ] reloading nginx configuration\n"
		nginx -s reload
    fi
}


if [ -z "$1" ];then
    printf "[ ${RED}ERROR${NC} ] provide param: prepare, fixperms or any docker-compose parameter\n"
    exit 1
fi
set -u

case "$1" in

    prepare)    sanity_check
                create_volume_host_path
                create_synapse_log_config
                create_synapse_homeserver_yaml
                render_synapse_homeserver_yaml
                render_element_config_json
                chown_volume_host_paths
                create_nginx_reverse_proxy_config
                render_mautrix_whatsapp_config_yaml
                ;;

    clean)      clean
                ;;
    write-compose)   write_compose
	            ;;
    fixperms)   sanity_check
                chown_volume_host_paths
                ;;

    *)          render_compose_file_and_execute $@
                ;;

esac
