# NOTE: this project is oprhaned!

# Docker Matrix Bootstrap for Synology Diskstations

This project consists of a script to bootstrap a Matrix Synapse Server, an Element Webapp and a Postgresql Server based on Docker Containers.
It is specificly designed to work on a baremetal Synology Diskation NAS and will not work in any other environments!

## Supported Environments
Baremetal Synology Diskstations with Docker support.

Other environments (even if its inside a VM on a Synology Diskstation) are not supported and will result in a broken configuration.

## Precondition
The script expects (Let's Encrypt) certificates registered in Synology's certificate manager for:
- `SYNAPSE_SERVER_NAME`
- `ELEMENT_SERVER_NAME` (if ELEMENT_ENABLED=yes)

It will detect certificates either registered to a sub domain or wildcard domain.

Make sure to have seperate sub domains for Synapse and Element, as running them using the same sub domain is a [potential security risk](https://github.com/vector-im/element-web#important-security-notes). The Script will aboard the preparation step if both sub domains are identical!

## How to use
1. clone git project
2. edit variables in `config`
3. execute `sudo ./run.sh prepare`; only proceed with step 4 if no `ERROR` message occoured, otherwise the configuration will be broken!
4. execute `sudo ./run.sh up -d`
5. register user
- from cli: `docker exec -ti matrix_synapse_1  register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008`
- from self-hosted Element: `https://${ELEMENT_PUBLIC_BASEURL}/#/register` (if ELEMENT_ENABLED=yes)
6. login user in self-hosted Element: `https://${ELEMENT_PUBLIC_BASEURL}/#/login`(if ELEMENT_ENABLED=yes)

If `ELEMENT_ENABLED` is not `yes`, Element will not be deployed and you will have to use another client!

`run.sh` wraps calls to docker-compose, by rendering the variables into the docker-compose.template on the fly and uses the result with docker-compose. The `run.sh` script passes all options and parameters to docker-compose... Thus, whatever works with docker-compose directly, does work with it as well.

### Clean up
To perform a clean start, just run `sudo ./run.sh clean`. As a result the bind-mount source folders and the reverse proxy rules will be deleted.
Make sure to recreate the folders and config using `sudo ./run.sh prepare` before running `sudo ./run.sh up -d` again.

### Write docker-compose.yml to disk
If you choose to only use the script to bootstrap the initial configuration, you can run `sudo ./run.sh write-compose` to persist the generated docker-compose.yml to disk and use it with docker-compose.


## What does the prepare step do?
Basicly it creates and configures everything required to run the Matrix Synapse server:
1. It creates data folders for Matrix Synapse, Element and Postgresql and fixes file permissions
2. It generate a homeserver.yml, gathers instance unique information from it and renders a configured homeserver.yml
3. It creates a domain specific log configuration for Matrix Synapse and uses it in homeserver.yml
4. It generates an Element config.json
5. It creates a seperate reverse-proxy configuration for Synapse and Element

_The actions for Element are only performed, if `ELEMENT_ENABLED` is set to `yes` in config._

Though, it does not start the containers... this is done by executing `sudo ./run.sh up -d`.
