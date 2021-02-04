# Docker Matrix Bootstrap for Synology

This project consists of a script to bootstrap a Matrix Synapse Server, an Element Webapp and a Postgresql Server based on Docker Containers.
It is specificly designed to work on a Synology NAS.

## Precondition
The script expects (Let's Encrypt) certificates registered in Synology's certificate manager for:
- `SYNAPSE_SERVER_NAME`
- `ELEMENT_SERVER_NAME` (if ELEMENT_ENABLED=yes)

It will detect certificates either registered to a sub domain or wildcard domain.
Make sure to have seperate sub domains for Synapse and Element, as running them using the same sub domain is a potential security risk.

## How to use
1. clone git project
2. edit variables in `config`
3. execute `sudo ./run.sh prepare`
4. execute `./run.sh up -d`
5. register user
- from cli: `docker exec -ti matrix_synapse_1  register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008`
- from self-hosted Element: `https://${ELEMENT_PUBLIC_BASEURL}/#/register` (if ELEMENT_ENABLED=yes)
6. login user in self-hosted Element: `https://${ELEMENT_PUBLIC_BASEURL}/#/login`(if ELEMENT_ENABLED=yes)

If `ELEMENT_ENABLED` is not `yes`, Element will not be deployed and you will have to use another client!

`run.sh` wraps calls to docker-compose, by rendering the variables into the docker-compose.template on the fly and uses the result with docker-compose. The `run.sh` script passes all options and parameters to docker-compose... Thus, whatever works with docker-compose directly, does work with it as well.

## What does the prepare step do?
Basicly it creates and configures everything required to run the Matrix Synapse server:
1. It creates data folders for Matrix Synapse, Element and Postgresql and fixes file permissions
2. It generate a homeserver.yml, gathers instance unique information from it and renders an opionated homeserver.yml
3. It creates a domain specific log configuration for Matrix Synapse and uses it in homeserver.yml
4. It generates an Element config.json
5. It creates a seperate reverse-proxy configuration for Synapse and Element

_The actions for Element are only performed, if `ELEMENT_ENABLED` is set to `yes` in config._

Though, it does not start the containers... this is done by executing `./run.sh up -d`.
