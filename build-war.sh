#!/bin/bash

# Script to build CMDBuild WAR using Docker

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
GIT_REPO="${GIT_REPO:-https://github.com/genpat-it/cohesive-cmdbuild}"
GIT_BRANCH="${GIT_BRANCH:-main}"
GIT_TOKEN="${GIT_TOKEN:-}"
GIT_COMMIT="${GIT_COMMIT:-}"
OUTPUT_DIR="./output"
MAVEN_THREADS="${MAVEN_THREADS:-128}"
SKIP_SENCHA_TESTING="${SKIP_SENCHA_TESTING:-true}"
GIT_SSH_PORT="${GIT_SSH_PORT:-}"
KEEP_BUILDS="${KEEP_BUILDS:-5}"

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}CMDBuild WAR Builder${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "Repository: ${YELLOW}${GIT_REPO}${NC}"
echo -e "Branch: ${YELLOW}${GIT_BRANCH}${NC}"
if [ -n "${GIT_COMMIT}" ]; then
    echo -e "Commit: ${YELLOW}${GIT_COMMIT}${NC}"
fi
echo -e "Maven threads: ${YELLOW}${MAVEN_THREADS}${NC}"
echo -e "Skip Sencha testing: ${YELLOW}${SKIP_SENCHA_TESTING}${NC}"
echo -e "${GREEN}=========================================${NC}"

# Start total timer
T_TOTAL_START=$(date +%s)

# Create output directory
mkdir -p ${OUTPUT_DIR}

# Build the Docker image with BuildKit for caching
echo -e "\n${YELLOW}Building Docker image (using BuildKit with caching)...${NC}"

# Prepare secret for GIT_TOKEN (secure way - not stored in image history)
SECRET_ARG=""
if [ -n "${GIT_TOKEN}" ]; then
    # Create temporary file for the secret
    TOKEN_FILE=$(mktemp)
    echo -n "${GIT_TOKEN}" > "${TOKEN_FILE}"
    SECRET_ARG="--secret id=git_token,src=${TOKEN_FILE}"
    echo -e "Using GIT_TOKEN via BuildKit secret (secure)"
fi

COMMIT_ARG=""
if [ -n "${GIT_COMMIT}" ]; then
    COMMIT_ARG="--build-arg GIT_COMMIT=${GIT_COMMIT}"
fi

# Setup SSH agent forwarding for git clone inside Docker (if SSH URL used)
SSH_ARG=""
if echo "${GIT_REPO}" | grep -q "^git@\|^ssh://"; then
    # Start SSH agent if not running and load default key
    if [ -z "${SSH_AUTH_SOCK}" ]; then
        eval $(ssh-agent -s)
        STARTED_SSH_AGENT=true
    fi
    # Add key if agent has no identities
    if ! ssh-add -l &>/dev/null; then
        ssh-add 2>/dev/null || true
    fi
    SSH_ARG="--ssh default"
    echo -e "Using SSH agent forwarding for git clone"
fi

SSH_PORT_ARG=""
if [ -n "${GIT_SSH_PORT}" ]; then
    SSH_PORT_ARG="--build-arg GIT_SSH_PORT=${GIT_SSH_PORT}"
fi

T_BUILD_START=$(date +%s)

DOCKER_BUILDKIT=1 docker build \
    --build-arg GIT_REPO=${GIT_REPO} \
    --build-arg GIT_BRANCH=${GIT_BRANCH} \
    --build-arg MAVEN_THREADS=${MAVEN_THREADS} \
    --build-arg SKIP_SENCHA_TESTING=${SKIP_SENCHA_TESTING} \
    --build-arg CACHEBUST=$(date +%s) \
    ${COMMIT_ARG} \
    ${SECRET_ARG} \
    ${SSH_ARG} \
    ${SSH_PORT_ARG} \
    -t cmdbuild-builder:latest \
    . 2>&1 | tee ${OUTPUT_DIR}/build-$(date +%Y%m%d-%H%M%S).log

BUILD_RESULT=${PIPESTATUS[0]}
T_BUILD_END=$(date +%s)

# Clean up secret file and SSH agent
if [ -n "${TOKEN_FILE}" ] && [ -f "${TOKEN_FILE}" ]; then
    rm -f "${TOKEN_FILE}"
fi
if [ "${STARTED_SSH_AGENT}" = "true" ]; then
    eval $(ssh-agent -k) 2>/dev/null
fi

if [ ${BUILD_RESULT} -ne 0 ]; then
    echo -e "\n${RED}=========================================${NC}"
    echo -e "${RED}BUILD FAILED!${NC}"
    echo -e "${RED}=========================================${NC}"
    echo -e "Check log file in: ${YELLOW}${OUTPUT_DIR}/${NC}"
    exit 1
fi

# Extract the WAR file from the built image
T_EXTRACT_START=$(date +%s)
echo -e "\n${YELLOW}Extracting WAR file...${NC}"
CONTAINER_ID=$(docker create cmdbuild-builder:latest)
WAR_NAME="cohesive-$(date +%Y%m%d-%H%M%S).war"
docker cp ${CONTAINER_ID}:/cmdbuild-final.war ${OUTPUT_DIR}/${WAR_NAME}
docker rm ${CONTAINER_ID} > /dev/null
T_EXTRACT_END=$(date +%s)

# Create symlink to latest WAR
ln -sf "${WAR_NAME}" ${OUTPUT_DIR}/cohesive-latest.war

# Verify WAR
echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}BUILD COMPLETED SUCCESSFULLY!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "WAR file:  ${YELLOW}${OUTPUT_DIR}/${WAR_NAME}${NC}"
echo -e "Symlink:   ${YELLOW}${OUTPUT_DIR}/cohesive-latest.war${NC}"
ls -lh ${OUTPUT_DIR}/${WAR_NAME}
echo -e "\n${GREEN}Verifying WAR contents:${NC}"
unzip -l ${OUTPUT_DIR}/${WAR_NAME} | tail -1
echo -e "\nChecking for ui_dev/:"
UI_DEV_COUNT=$(unzip -l ${OUTPUT_DIR}/${WAR_NAME} | grep -c "ui_dev/" 2>/dev/null || true)
UI_DEV_COUNT=${UI_DEV_COUNT:-0}
if [ "${SKIP_SENCHA_TESTING}" = "true" ]; then
    if [ "$UI_DEV_COUNT" -le "1" ]; then
        echo -e "${GREEN}✓ ui_dev/ absent as expected (SKIP_SENCHA_TESTING=true)${NC}"
    else
        echo -e "${YELLOW}⚠ ui_dev/ found ($UI_DEV_COUNT files) despite SKIP_SENCHA_TESTING=true${NC}"
    fi
else
    if [ "$UI_DEV_COUNT" -gt "1000" ]; then
        echo -e "${GREEN}✓ ui_dev/ found ($UI_DEV_COUNT files)${NC}"
    else
        echo -e "${RED}✗ ui_dev/ missing or incomplete ($UI_DEV_COUNT files)${NC}"
    fi
fi

# Timing summary
T_TOTAL_END=$(date +%s)
T_BUILD=$((T_BUILD_END - T_BUILD_START))
T_EXTRACT=$((T_EXTRACT_END - T_EXTRACT_START))
T_TOTAL=$((T_TOTAL_END - T_TOTAL_START))

echo -e "\n${CYAN}=========================================${NC}"
echo -e "${CYAN}Build Timing${NC}"
echo -e "${CYAN}=========================================${NC}"
printf "${CYAN}Docker build:  %d:%02d${NC}\n" $((T_BUILD/60)) $((T_BUILD%60))
printf "${CYAN}WAR extract:   %d:%02d${NC}\n" $((T_EXTRACT/60)) $((T_EXTRACT%60))
printf "${CYAN}─────────────────────${NC}\n"
printf "${CYAN}Total:         %d:%02d${NC}\n" $((T_TOTAL/60)) $((T_TOTAL%60))
echo -e "${CYAN}=========================================${NC}"

# Clean up old builds (keep last N)
WAR_COUNT=$(ls -1 ${OUTPUT_DIR}/cohesive-2*.war 2>/dev/null | wc -l)
if [ "${WAR_COUNT}" -gt "${KEEP_BUILDS}" ]; then
    OLD_COUNT=$((WAR_COUNT - KEEP_BUILDS))
    echo -e "\n${YELLOW}Cleaning up old builds (keeping last ${KEEP_BUILDS})...${NC}"
    ls -1t ${OUTPUT_DIR}/cohesive-2*.war | tail -n ${OLD_COUNT} | while read f; do
        echo -e "  Removing $(basename $f)"
        rm -f "$f"
    done
    # Also clean old logs
    ls -1t ${OUTPUT_DIR}/build-*.log 2>/dev/null | tail -n +$((KEEP_BUILDS + 1)) | xargs rm -f 2>/dev/null || true
fi

echo -e "\n${GREEN}=========================================${NC}"
