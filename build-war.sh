#!/bin/bash

# Script to build CMDBuild WAR using Docker
# Uses Dockerfile.build (corrected version without UI restore bug)

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
GIT_REPO="${GIT_REPO:-https://github.com/genpat-it/cohesive-cmdbuild}"
GIT_BRANCH="${GIT_BRANCH:-main}"
GIT_TOKEN="${GIT_TOKEN:-}"
GIT_COMMIT="${GIT_COMMIT:-}"
OUTPUT_DIR="./output"
MAVEN_THREADS="${MAVEN_THREADS:-128}"

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}CMDBuild WAR Builder${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "Repository: ${YELLOW}${GIT_REPO}${NC}"
echo -e "Branch: ${YELLOW}${GIT_BRANCH}${NC}"
if [ -n "${GIT_COMMIT}" ]; then
    echo -e "Commit: ${YELLOW}${GIT_COMMIT}${NC}"
fi
echo -e "Maven threads: ${YELLOW}${MAVEN_THREADS}${NC}"
echo -e "${GREEN}=========================================${NC}"

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

DOCKER_BUILDKIT=1 docker build \
    --build-arg GIT_REPO=${GIT_REPO} \
    --build-arg GIT_BRANCH=${GIT_BRANCH} \
    --build-arg MAVEN_THREADS=${MAVEN_THREADS} \
    --build-arg CACHEBUST=$(date +%s) \
    ${COMMIT_ARG} \
    ${SECRET_ARG} \
    -t cmdbuild-builder:latest \
    . 2>&1 | tee ${OUTPUT_DIR}/build-$(date +%Y%m%d-%H%M%S).log

BUILD_RESULT=${PIPESTATUS[0]}

# Clean up secret file
if [ -n "${TOKEN_FILE}" ] && [ -f "${TOKEN_FILE}" ]; then
    rm -f "${TOKEN_FILE}"
fi

if [ ${BUILD_RESULT} -ne 0 ]; then
    echo -e "\n${RED}=========================================${NC}"
    echo -e "${RED}BUILD FAILED!${NC}"
    echo -e "${RED}=========================================${NC}"
    echo -e "Check log file in: ${YELLOW}${OUTPUT_DIR}/${NC}"
    exit 1
fi

# Extract the WAR file from the built image
echo -e "\n${YELLOW}Extracting WAR file...${NC}"
CONTAINER_ID=$(docker create cmdbuild-builder:latest)
WAR_NAME="cohesive-$(date +%Y%m%d-%H%M%S).war"
docker cp ${CONTAINER_ID}:/cmdbuild-final.war ${OUTPUT_DIR}/${WAR_NAME}
docker rm ${CONTAINER_ID}

echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}BUILD COMPLETED SUCCESSFULLY!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "WAR file: ${YELLOW}${OUTPUT_DIR}/${WAR_NAME}${NC}"
ls -lh ${OUTPUT_DIR}/${WAR_NAME}
echo -e "\n${GREEN}Verifying WAR contents:${NC}"
unzip -l ${OUTPUT_DIR}/${WAR_NAME} | tail -1
echo -e "\nChecking for ui_dev/:"
UI_DEV_COUNT=$(unzip -l ${OUTPUT_DIR}/${WAR_NAME} | grep -c "ui_dev/" || echo "0")
if [ "$UI_DEV_COUNT" -gt "1000" ]; then
    echo -e "${GREEN}✓ ui_dev/ found ($UI_DEV_COUNT files)${NC}"
else
    echo -e "${RED}✗ ui_dev/ missing or incomplete ($UI_DEV_COUNT files)${NC}"
fi
echo -e "${GREEN}=========================================${NC}"
