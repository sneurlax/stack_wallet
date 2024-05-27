#!/usr/bin/env bash

set -x -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <theme specific assets dir name (ex. stack_wallet)>"
    exit 1
fi

SELECT_ASSETS_DIR=$1

# declare full paths
ASSET_SOURCES_DIR="${APP_PROJECT_ROOT_DIR}/asset_sources"
ASSETS_DIR="${APP_PROJECT_ROOT_DIR}/assets"


# finally update symlinks

rm -f "${ASSETS_DIR}/default_themes"
ln -s "${ASSET_SOURCES_DIR}/bundled_themes/${SELECT_ASSETS_DIR}" "${ASSETS_DIR}/default_themes"

rm -f "${ASSETS_DIR}/icon"
ln -s "${ASSET_SOURCES_DIR}/icon/${SELECT_ASSETS_DIR}" "${ASSETS_DIR}/icon"

rm -f "${ASSETS_DIR}/lottie"
ln -s "${ASSET_SOURCES_DIR}/lottie/${SELECT_ASSETS_DIR}" "${ASSETS_DIR}/lottie"

rm -f "${ASSETS_DIR}/in_app_logo_icons"
ln -s "${ASSET_SOURCES_DIR}/in_app_logo_icons/${SELECT_ASSETS_DIR}" "${ASSETS_DIR}/in_app_logo_icons"