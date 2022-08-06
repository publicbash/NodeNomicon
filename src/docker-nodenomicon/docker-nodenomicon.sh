#!/bin/bash

# -----------------------------------------------------------------------------
# 'NodeNomicon' image wrapper
#
# Kaleb - 2022-08-06
# -----------------------------------------------------------------------------

SUDO_CMD="$( command -v sudo )"
[[ "$SUDO_CMD" == "" ]] && DOCKER_CMD="docker" || DOCKER_CMD="$SUDO_CMD docker"

IMAGE_NAME="nodenomicon"
DIR_CONF_POOL="$(pwd)/conf-pool"
DIR_WORK="$(pwd)/work"

[[ ! -d $DIR_CONF_POOL ]] && mkdir -p $DIR_CONF_POOL
[[ ! -d $DIR_WORK ]] && mkdir -p $DIR_WORK

$DOCKER_CMD run \
	-v $DIR_CONF_POOL:/etc/nodenomicon \
	-v $DIR_WORK:/nodenomicon/work \
	$IMAGE_NAME $@
