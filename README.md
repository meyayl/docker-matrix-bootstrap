# Docker Matrix Bootstrap for Synology

This project consists of a script to bootstrap a Matrix Synapse Server, an Element Webapp and a Postgresql Server based on Docker Containers.
It is specificly designed to work on a Synology NAS.

## Precondition
The script expects a (Lets Encrypt) certificate registered to the `SYNAPSE_SERVER_NAME` in Synology's certificate manager.

## How to use
1. clone git project
2. edit variables in `config`
3. execute `sudo ./run.sh prepare`
4. execute `./run.sh up -d`
5. register user
- from cli: `docker exec -ti matrix_synapse_1  register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008`
- from self-hosted element: `https://${SYNAPSE_PUBLIC_BASEURL}/#/register`
6. login user in self-hosted element: `https://${SYNAPSE_PUBLIC_BASEURL}/#/login`

`run.sh` wraps calls to docker-compose, by rendering the variables into the docker-compose.template on the fly and uses the result with docker-compose. The `run.sh` script passes all options and parameters to docker-compose... Thus, whatever works with docker-compose directly, does work with it as well.

## What does the prepare step do?
Basicly it creates and configures everything required to run the Matrix Synapse server:
1. It creates data folders for Matrix Synapse, Element and Postgresql and fixes file permissions
2. It generate a homeserver.yml, gathers instance unique information from it and renders an opionated homeserver.yml
3. It create a domain specific log configuration for Matrix Synapse and uses it in homeserver.yml
4. It generates an Element config.json
5. It creates a reverse-proxy configuration for Synapse and Element

Though, it does not start the containers... this is done by executing `./run.sh up -d`
