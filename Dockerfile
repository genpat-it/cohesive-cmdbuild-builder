# syntax=docker/dockerfile:1
FROM maven:3.8.6-eclipse-temurin-17

# Build arguments
ARG GIT_REPO=https://github.com/genpat-it/cohesive-cmdbuild
ARG GIT_BRANCH=main
ARG GIT_TOKEN=""
ARG MAVEN_THREADS=128

# Install dependencies and Java 8 (for Sencha Cmd)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y \
    wget curl unzip zip ruby ruby-dev rsync git openjdk-8-jdk \
    && rm -rf /var/lib/apt/lists/*

# Download and install libssl1.1 for PhantomJS
RUN --mount=type=cache,target=/tmp/cache \
    wget http://snapshot.debian.org/archive/debian/20230611T025313Z/pool/main/o/openssl/libssl1.1_1.1.1n-0+deb11u5_amd64.deb -O /tmp/cache/libssl1.1.deb \
    && dpkg -i /tmp/cache/libssl1.1.deb

# Install Sencha Cmd 6.2.2.36
RUN --mount=type=cache,target=/tmp/cache \
    if [ ! -f /tmp/cache/sencha.zip ]; then \
        wget -q http://cdn.sencha.com/cmd/6.2.2.36/no-jre/SenchaCmd-6.2.2.36-linux-amd64.sh.zip -O /tmp/cache/sencha.zip; \
    fi && \
    unzip /tmp/cache/sencha.zip -d /tmp && \
    chmod +x /tmp/SenchaCmd-6.2.2.36-linux-amd64.sh && \
    JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64 /tmp/SenchaCmd-6.2.2.36-linux-amd64.sh -q && \
    rm -rf /tmp/SenchaCmd-6.2.2.36-linux-amd64.sh

# Create wrapper script for sencha with Java 8
RUN mv /root/bin/Sencha/Cmd/sencha /root/bin/Sencha/Cmd/sencha-original && \
    echo '#!/bin/bash' > /root/bin/Sencha/Cmd/sencha && \
    echo 'export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64' >> /root/bin/Sencha/Cmd/sencha && \
    echo 'export OPENSSL_CONF=/dev/null' >> /root/bin/Sencha/Cmd/sencha && \
    echo 'exec /root/bin/Sencha/Cmd/sencha-original "$@"' >> /root/bin/Sencha/Cmd/sencha && \
    chmod +x /root/bin/Sencha/Cmd/sencha

ENV PATH="/root/bin/Sencha/Cmd:${PATH}"

WORKDIR /build

# Clone repository
RUN --mount=type=cache,target=/root/.gitcache \
    echo "=========================================" && \
    echo "Cloning repository" && \
    echo "Repository: ${GIT_REPO}" && \
    echo "Branch: ${GIT_BRANCH}" && \
    echo "=========================================" && \
    if [ -n "${GIT_TOKEN}" ]; then \
        REPO_WITH_TOKEN=$(echo ${GIT_REPO} | sed "s|://|://${GIT_TOKEN}@|"); \
        git clone --branch ${GIT_BRANCH} --single-branch --depth 1 ${REPO_WITH_TOKEN} cmdbuild-ui; \
    else \
        git clone --branch ${GIT_BRANCH} --single-branch --depth 1 ${GIT_REPO} cmdbuild-ui; \
    fi && \
    echo "✓ Repository cloned successfully"

WORKDIR /build/cmdbuild-ui/cmdbuild-3.4.3-src

# Fix Maven dependencies
RUN echo "=========================================" && \
    echo "Fixing Maven dependencies" && \
    echo "=========================================" && \
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

# Build with Maven - Using cache mount for Maven repository
RUN --mount=type=cache,target=/root/.m2,sharing=locked \
    echo "=========================================" && \
    echo "Building with Maven (threads: ${MAVEN_THREADS})" && \
    echo "=========================================" && \
    echo "Syncing UI sources..." && \
    rsync -rWI ui/izsam/src ui/app/ && \
    echo "Removing conflicting UI directories..." && \
    rm -rf ui/app/view/contextmenucomponents ui/app/view/custompages && \
    echo "Starting Maven build..." && \
    if [ "${MAVEN_THREADS}" = "1" ]; then \
        mvn -B -am -pl cmdbuild clean install -DskipTests; \
    else \
        mvn -B -T ${MAVEN_THREADS} -am -pl cmdbuild clean install -DskipTests; \
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
    echo "Adding configuration files to WAR" && \
    echo "=========================================" && \
    cd /tmp && \
    # Extract WAR \
    unzip -q /cmdbuild-built.war -d /tmp/war && \
    # Copy all WEB-INF files from template (web.xml + all .conf files + sql/) \
    cp -r /tmp/webinf-template/web.xml /tmp/war/WEB-INF/ && \
    echo "✓ web.xml added" && \
    cp -r /tmp/webinf-template/conf /tmp/war/WEB-INF/ && \
    echo "✓ All configuration files copied" && \
    cp -r /tmp/webinf-template/sql /tmp/war/WEB-INF/ && \
    echo "✓ SQL directories added (functions/ and patches/)" && \
    echo "✓ Database configuration included:" && \
    cat /tmp/war/WEB-INF/conf/database.conf && \
    # Rebuild WAR \
    cd /tmp/war && \
    zip -q -r /cmdbuild-final.war . && \
    echo "✓ Final WAR created" && \
    ls -lh /cmdbuild-final.war && \
    # Show statistics \
    echo "" && \
    echo "WAR Statistics:" && \
    unzip -l /cmdbuild-final.war | tail -1 && \
    echo "" && \
    echo "Checking for ui_dev/:" && \
    unzip -l /cmdbuild-final.war | grep -c "ui_dev/" || echo "WARNING: ui_dev/ not found!"

CMD ["bash"]
