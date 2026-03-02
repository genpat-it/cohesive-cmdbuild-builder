# syntax=docker/dockerfile:1
# Requires base image: docker build -f Dockerfile.base -t cmdbuild-builder-base:latest .
FROM cmdbuild-builder-base:latest AS builder

# Build arguments
ARG GIT_REPO=https://github.com/genpat-it/cohesive-cmdbuild
ARG GIT_BRANCH=main
ARG MAVEN_THREADS=128
ARG SKIP_SENCHA_TESTING=false
ARG GIT_SSH_PORT=
# Note: GIT_TOKEN is now passed via BuildKit secrets for security

WORKDIR /build

# Cache buster to force fresh git clone on each build
ARG CACHEBUST=1
ARG GIT_COMMIT=

# Clone repository (supports SSH agent forwarding, token secret, or public HTTP)
RUN --mount=type=cache,target=/root/.gitcache \
    --mount=type=secret,id=git_token,required=false \
    --mount=type=ssh \
    echo "Cache invalidation: ${CACHEBUST}" && \
    echo "=========================================" && \
    echo "Cloning repository" && \
    echo "Repository: ${GIT_REPO}" && \
    echo "Branch: ${GIT_BRANCH}" && \
    if [ -n "${GIT_COMMIT}" ]; then echo "Commit: ${GIT_COMMIT}"; fi && \
    echo "=========================================" && \
    # Configure SSH for git clone (skip host key check, optional custom port) \
    mkdir -p ~/.ssh && \
    printf "Host *\n  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\n" > ~/.ssh/config && \
    if [ -n "${GIT_SSH_PORT}" ]; then \
        printf "  Port %s\n" "${GIT_SSH_PORT}" >> ~/.ssh/config; \
    fi && \
    if [ -f /run/secrets/git_token ]; then \
        GIT_TOKEN=$(cat /run/secrets/git_token) && \
        REPO=$(echo ${GIT_REPO} | sed "s|://|://${GIT_TOKEN}@|"); \
    else \
        REPO=${GIT_REPO}; \
    fi && \
    if [ -n "${GIT_COMMIT}" ]; then \
        git clone --branch ${GIT_BRANCH} --single-branch ${REPO} cmdbuild-ui && \
        cd cmdbuild-ui && git checkout ${GIT_COMMIT} && cd ..; \
    else \
        git clone --branch ${GIT_BRANCH} --single-branch --depth 1 ${REPO} cmdbuild-ui; \
    fi && \
    rm -f ~/.ssh/config && \
    echo "✓ Repository cloned successfully"

# Pre-build string replacements (applied to source before Maven)
COPY pre-build-apply.sh /tmp/pre-build-apply.sh
RUN chmod +x /tmp/pre-build-apply.sh && /tmp/pre-build-apply.sh

WORKDIR /build/cmdbuild-ui/cmdbuild-3.4.3-src

# Fix Maven dependencies
RUN echo "=========================================" && \
    echo "Fixing Maven dependencies" && \
    echo "=========================================" && \
    # Add Maven Central repository to root pom.xml to resolve jTDS
    sed -i '/<repositories>/,/<\/repositories>/d' pom.xml 2>/dev/null || true && \
    sed -i '/<\/project>/i \
    <repositories>\
        <repository>\
            <id>central</id>\
            <url>https://repo1.maven.org/maven2</url>\
        </repository>\
        <repository>\
            <id>atlassian</id>\
            <url>https://maven.atlassian.com/content/groups/public</url>\
        </repository>\
    </repositories>' pom.xml && \
    echo "✓ Added Maven Central repository" && \
    cd ui && \
    sed -i '161 a\                    <dependency>\n                        <groupId>com.google.guava</groupId>\n                        <artifactId>guava</artifactId>\n                        <version>30.1-jre</version>\n                    </dependency>' pom.xml && \
    echo "✓ Guava dependency fixed" && \
    cd ../core/access && \
    sed -i 's/<version>3.4.1-DEV-SNAPSHOT<\/version>/<version>${project.version}<\/version>/g' pom.xml && \
    echo "✓ Fixed version mismatch in core-access" && \
    cd ../../dao/sql && \
    mkdir -p src/main/resources && \
    echo "✓ Created missing resources directory for dao-sql" && \
    cd ../../cmdbuild && \
    sed -i '/<dependency>/{:a;N;/<\/dependency>/!ba;/<artifactId>cmdbuild-dao-sql<\/artifactId>/d}' pom.xml && \
    sed -i '/<execution>/{:a;N;/<\/execution>/!ba;/<id>unpack-sql<\/id>/d}' pom.xml && \
    echo "✓ Removed problematic cmdbuild-dao-sql:zip dependency and unpack-sql execution"

# Optionally skip Sencha testing build (saves ~2:48 min)
RUN if [ "${SKIP_SENCHA_TESTING}" = "true" ]; then \
        echo "=========================================" && \
        echo "Skipping Sencha testing build (SKIP_SENCHA_TESTING=true)" && \
        echo "=========================================" && \
        # Remove the sencha-app-build-testing <execution> block from ui/pom.xml
        perl -0777 -i -pe 's/<execution>\s*<id>sencha-app-build-testing<\/id>.*?<\/execution>\s*//s' ui/pom.xml && \
        echo "✓ Removed sencha-app-build-testing execution" && \
        # Remove the <resource> block that maps build/testing/CMDBuildUI → ui_dev
        perl -0777 -i -pe 's/<resource>\s*<directory>build\/testing\/CMDBuildUI<\/directory>\s*<targetPath>ui_dev<\/targetPath>\s*<\/resource>\s*//s' ui/pom.xml && \
        echo "✓ Removed ui_dev resource mapping" && \
        echo "✓ Testing build will be skipped"; \
    else \
        echo "Sencha testing build enabled (SKIP_SENCHA_TESTING=false)"; \
    fi

# Build with Maven - Using cache mount for Maven repository
RUN --mount=type=cache,target=/root/.m2/repository,sharing=locked \
    echo "=========================================" && \
    echo "Building with Maven (threads: ${MAVEN_THREADS})" && \
    echo "=========================================" && \
    echo "Clearing cached jTDS to force re-download from Central..." && \
    rm -rf /root/.m2/repository/net/sourceforge/jtds 2>/dev/null || true && \
    echo "Syncing UI sources..." && \
    rsync -rWI ui/izsam/src ui/app/ && \
    echo "Removing conflicting UI directories..." && \
    rm -rf ui/app/view/contextmenucomponents ui/app/view/custompages && \
    echo "Starting Maven build..." && \
    if [ "${MAVEN_THREADS}" = "1" ]; then \
        mvn -B -s /root/.m2/settings.xml -am -pl cmdbuild clean install -DskipTests; \
    else \
        mvn -B -s /root/.m2/settings.xml -T ${MAVEN_THREADS} -am -pl cmdbuild clean install -DskipTests; \
    fi && \
    echo "✓ Build completed successfully"

# Find and prepare WAR
RUN echo "=========================================" && \
    echo "Preparing WAR file" && \
    echo "=========================================" && \
    WAR_FILE=$(find /build/cmdbuild-ui/cmdbuild-3.4.3-src/cmdbuild/target -name "cmdbuild.war" -type f | head -1) && \
    if [ -n "$WAR_FILE" ]; then \
        cp "$WAR_FILE" /cmdbuild-built.war && \
        echo "✓ WAR file prepared: /cmdbuild-built.war" && \
        ls -lh /cmdbuild-built.war; \
    else \
        echo "ERROR: WAR file not found!"; \
        find /build -name "*.war" -type f; \
        exit 1; \
    fi

# Copy WEB-INF configuration files
COPY WEB-INF /tmp/webinf-template

RUN echo "=========================================" && \
    echo "Adding configuration files to WAR (in-place)" && \
    echo "=========================================" && \
    cp /cmdbuild-built.war /cmdbuild-final.war && \
    # Prepare WEB-INF overlay in a temp directory \
    mkdir -p /tmp/war-overlay/WEB-INF/conf /tmp/war-overlay/WEB-INF/sql && \
    cp /tmp/webinf-template/web.xml /tmp/war-overlay/WEB-INF/ && \
    echo "✓ web.xml prepared" && \
    cp -r /tmp/webinf-template/conf/* /tmp/war-overlay/WEB-INF/conf/ && \
    echo "✓ Configuration files prepared" && \
    cp -r /tmp/webinf-template/sql/* /tmp/war-overlay/WEB-INF/sql/ 2>/dev/null || true && \
    echo "✓ SQL directories prepared" && \
    echo "Database configuration:" && \
    cat /tmp/war-overlay/WEB-INF/conf/database.conf && \
    # Add/update files directly into WAR without full extract \
    cd /tmp/war-overlay && \
    zip -q -r /cmdbuild-final.war . && \
    echo "✓ Configuration injected into WAR" && \
    rm -rf /tmp/war-overlay && \
    echo "✓ Final WAR created" && \
    ls -lh /cmdbuild-final.war && \
    echo "" && \
    echo "WAR Statistics:" && \
    unzip -l /cmdbuild-final.war | tail -1 && \
    echo "" && \
    echo "Checking for ui_dev/:" && \
    unzip -l /cmdbuild-final.war | grep -c "ui_dev/" || echo "ui_dev/ not found (expected if SKIP_SENCHA_TESTING=true)"

# === Stage 2: Minimal export image (only the WAR) ===
FROM alpine:latest
COPY --from=builder /cmdbuild-final.war /cmdbuild-final.war
CMD ["echo", "WAR file: /cmdbuild-final.war"]
