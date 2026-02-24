#!/bin/bash

# hotpatch-war.sh - Inject modified files into a CMDBuild WAR without rebuilding
#
# Usage:
#   ./hotpatch-war.sh <war-file> <patch-dir>
#
# The patch directory should mirror the WAR's internal structure:
#   patch-dir/
#   ├── ui/              → production UI files
#   ├── ui_dev/          → testing/debug UI files
#   └── WEB-INF/         → configuration files
#
# Example: patch a locale file
#   mkdir -p patch/ui/app/locales
#   cp my-locale-it.js patch/ui/app/locales/locale-it.js
#   ./hotpatch-war.sh ./output/cohesive-latest.war ./patch

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Usage check
if [ $# -lt 2 ]; then
    echo -e "${RED}Usage: $0 <war-file> <patch-dir>${NC}"
    echo ""
    echo "Inject modified files into an existing CMDBuild WAR."
    echo ""
    echo "Arguments:"
    echo "  war-file    Path to the WAR file to patch"
    echo "  patch-dir   Directory with files to inject (mirrors WAR structure)"
    echo ""
    echo "Example:"
    echo "  mkdir -p patch/ui/app/locales"
    echo "  cp locale-it.js patch/ui/app/locales/"
    echo "  $0 ./output/cohesive-latest.war ./patch"
    exit 1
fi

WAR_FILE="$(realpath "$1")"
PATCH_DIR="$(realpath "$2")"

# Validate inputs
if [ ! -f "${WAR_FILE}" ]; then
    echo -e "${RED}Error: WAR file not found: ${WAR_FILE}${NC}"
    exit 1
fi

if [ ! -d "${PATCH_DIR}" ]; then
    echo -e "${RED}Error: Patch directory not found: ${PATCH_DIR}${NC}"
    exit 1
fi

# Check that patch dir has content
FILE_COUNT=$(find "${PATCH_DIR}" -type f | wc -l)
if [ "${FILE_COUNT}" -eq 0 ]; then
    echo -e "${RED}Error: Patch directory is empty${NC}"
    exit 1
fi

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}CMDBuild WAR Hotpatch${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "WAR file:  ${YELLOW}${WAR_FILE}${NC}"
echo -e "Patch dir: ${YELLOW}${PATCH_DIR}${NC}"
echo -e "Files:     ${YELLOW}${FILE_COUNT}${NC}"
echo -e "${GREEN}=========================================${NC}"

# List files to be injected
echo -e "\n${YELLOW}Files to inject:${NC}"
(cd "${PATCH_DIR}" && find . -type f | sed 's|^\./||' | sort)

# Inject files into WAR using zip -r (adds or updates)
echo -e "\n${YELLOW}Patching WAR...${NC}"
(cd "${PATCH_DIR}" && zip -r "${WAR_FILE}" . -x '.*')

echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}HOTPATCH COMPLETED${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "Patched WAR: ${YELLOW}${WAR_FILE}${NC}"
ls -lh "${WAR_FILE}"

# Verify patched files
echo -e "\n${YELLOW}Verifying patched files:${NC}"
(cd "${PATCH_DIR}" && find . -type f | sed 's|^\./||' | sort | while read -r f; do
    if unzip -l "${WAR_FILE}" "${f}" 2>/dev/null | grep -q "${f}"; then
        echo -e "  ${GREEN}✓${NC} ${f}"
    else
        echo -e "  ${RED}✗${NC} ${f} (NOT FOUND in WAR)"
    fi
done)
