#!/bin/bash

# Script to deploy the built WAR to Tomcat via Manager
# Usage: TOMCAT_URL=http://localhost:8080 TOMCAT_USER=admin TOMCAT_PASS=password ./deploy-war.sh

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration from environment variables
TOMCAT_URL="${TOMCAT_URL:-http://localhost:8080}"
TOMCAT_USER="${TOMCAT_USER:-}"
TOMCAT_PASS="${TOMCAT_PASS:-}"
TOMCAT_AUTH_HEADER="${TOMCAT_AUTH_HEADER:-}"  # Optional: pre-encoded Basic auth header
APP_CONTEXT="${APP_CONTEXT:-cohesive}"
OUTPUT_DIR="./output"

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}COHESIVE WAR Deployment${NC}"
echo -e "${GREEN}=========================================${NC}"

# Check if authentication is provided
if [ -z "$TOMCAT_AUTH_HEADER" ] && ([ -z "$TOMCAT_USER" ] || [ -z "$TOMCAT_PASS" ]); then
    echo -e "${RED}Error: Authentication credentials must be provided${NC}"
    echo ""
    echo "Usage (Option 1 - username/password):"
    echo "  TOMCAT_URL=http://localhost:8080 \\"
    echo "  TOMCAT_USER=admin \\"
    echo "  TOMCAT_PASS=password \\"
    echo "  ./deploy-war.sh"
    echo ""
    echo "Usage (Option 2 - pre-encoded Basic auth header):"
    echo "  TOMCAT_URL=http://localhost:8080 \\"
    echo "  TOMCAT_AUTH_HEADER='Basic YWRtaW46cGFzc3dvcmQ=' \\"
    echo "  ./deploy-war.sh"
    echo ""
    echo "Optional variables:"
    echo "  APP_CONTEXT=cohesive    # Application context path (default: cohesive)"
    exit 1
fi

# Set up curl authentication
if [ -n "$TOMCAT_AUTH_HEADER" ]; then
    # Use pre-encoded auth header (Jenkins style)
    CURL_AUTH="-H 'Authorization: ${TOMCAT_AUTH_HEADER}'"
else
    # Use username:password (traditional)
    CURL_AUTH="-u ${TOMCAT_USER}:${TOMCAT_PASS}"
fi

# Find the most recent WAR file
WAR_FILE=$(ls -t ${OUTPUT_DIR}/cohesive-*.war 2>/dev/null | head -1)

if [ -z "$WAR_FILE" ]; then
    echo -e "${RED}Error: No WAR file found in ${OUTPUT_DIR}/${NC}"
    echo "Please build the WAR first using ./build-war.sh"
    exit 1
fi

echo -e "Tomcat URL: ${YELLOW}${TOMCAT_URL}${NC}"
echo -e "App context: ${YELLOW}/${APP_CONTEXT}${NC}"
echo -e "WAR file: ${YELLOW}${WAR_FILE}${NC}"
echo -e "${GREEN}=========================================${NC}"

# Check if application is already deployed
echo -e "\n${YELLOW}Checking if application is already deployed...${NC}"
APP_STATUS=$(eval curl -s ${CURL_AUTH} \
    "${TOMCAT_URL}/manager/text/list" | grep "^/${APP_CONTEXT}:" || echo "")

if [ -n "$APP_STATUS" ]; then
    echo -e "${YELLOW}Application found: ${APP_STATUS}${NC}"
    echo -e "${YELLOW}Undeploying existing application...${NC}"

    UNDEPLOY_RESULT=$(eval curl -s ${CURL_AUTH} \
        "${TOMCAT_URL}/manager/text/undeploy?path=/${APP_CONTEXT}")

    if echo "$UNDEPLOY_RESULT" | grep -q "OK"; then
        echo -e "${GREEN}✓ Undeployed successfully${NC}"
    else
        echo -e "${RED}✗ Undeploy failed: ${UNDEPLOY_RESULT}${NC}"
        exit 1
    fi
fi

# Deploy the new WAR
echo -e "\n${YELLOW}Deploying WAR to Tomcat...${NC}"
DEPLOY_RESULT=$(eval curl -s ${CURL_AUTH} \
    -T "${WAR_FILE}" \
    "${TOMCAT_URL}/manager/text/deploy?path=/${APP_CONTEXT}&update=true")

if echo "$DEPLOY_RESULT" | grep -q "OK"; then
    echo -e "${GREEN}✓ Deployed successfully${NC}"

    # Wait a moment for deployment to initialize
    echo -e "\n${YELLOW}Waiting for application to start...${NC}"
    sleep 5

    # Check application status
    APP_STATUS=$(eval curl -s ${CURL_AUTH} \
        "${TOMCAT_URL}/manager/text/list" | grep "^/${APP_CONTEXT}:")

    echo -e "${GREEN}Application status: ${APP_STATUS}${NC}"

    echo -e "\n${GREEN}=========================================${NC}"
    echo -e "${GREEN}DEPLOYMENT COMPLETED!${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo -e "Application URL: ${YELLOW}${TOMCAT_URL}/${APP_CONTEXT}${NC}"
    echo -e "${GREEN}=========================================${NC}"
else
    echo -e "${RED}✗ Deployment failed: ${DEPLOY_RESULT}${NC}"
    exit 1
fi
