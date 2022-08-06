#!/bin/bash

# -----------------------------------------------------------------------------
# Docker build routine for 'nodenomicon'.
#
# Kaleb - 2022-08-06
# -----------------------------------------------------------------------------

# ---- Config -----------------------------------------------------------------
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
GIT_REPO="https://github.com/publicbash/NodeNomicon.git"

# ---- Entry Point ------------------------------------------------------------

# Clear source app, if exists.
[[ -d ./nodenomicon ]] && rm -rf ./nodenomicon

# Download NodeNomicon source
git clone $GIT_REPO nodenomicon

# Clear git metadata
[[ -d ./nodenomicon/.git ]] && rm -rf ./nodenomicon/.git

# Build image
docker build --tag nodenomicon .

# After the build process, free some space by removing source app again.
[[ -d ./nodenomicon ]] && rm -rf ./nodenomicon
