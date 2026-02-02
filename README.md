# Cohesive WAR Builder for CMDBuild

A Docker-based build system that **compiles and packages** the [cohesive-cmdbuild](https://github.com/genpat-it/cohesive-cmdbuild) source code into a production-ready WAR file.

## What is this?

This is a **builder tool** that takes the CMDBuild source code from https://github.com/genpat-it/cohesive-cmdbuild and produces a complete, deployable WAR file.

**What it does:**
- 📥 Clones the cohesive-cmdbuild source repository
- 🔨 Compiles Java backend with Maven (128 parallel threads)
- 🎨 Builds custom UI with Sencha Cmd
- 📦 Packages everything into a single WAR file
- ⚙️ Includes your configuration files automatically

**What you get:**
A production-ready `cohesive-YYYYMMDD-HHMMSS.war` (~390MB) that contains:
- ✅ CMDBuild application (compiled Java backend)
- ✅ Custom UI (compiled with Sencha Cmd)
- ✅ All configuration files (`WEB-INF/web.xml`, `WEB-INF/conf/*.conf`)
- ✅ Required directory structure (`WEB-INF/sql/functions/`, `WEB-INF/sql/patches/`)
- ✅ Your database configuration (from `WEB-INF/conf/database.conf`)

**Ready to deploy** - just copy the WAR to your Tomcat server!

## Quick Start

### 1. Build the WAR

```bash
# Clone this repository
git clone https://github.com/genpat-it/cohesive-cmdbuild-builder.git
cd cohesive-cmdbuild-builder

# Configure database BEFORE building
nano WEB-INF/conf/database.conf

# Build the WAR (requires Docker)
GIT_REPO=https://github.com/genpat-it/cohesive-cmdbuild \
GIT_BRANCH=main \
./build-war.sh
```

The build process will:
- Clone your CMDBuild source code repository
- Compile Java backend with Maven
- Build custom UI with Sencha Cmd
- Package everything into a single, cohesive WAR file

**Output**: `./output/cohesive-YYYYMMDD-HHMMSS.war` (~390-420MB)

### 2. Deploy

You have two deployment options:

#### Option A: Manual Deployment

1. Copy `./output/cohesive-*.war` to your Tomcat `webapps/` directory
2. Start Tomcat (must run as non-root user, e.g., `tomcat` or `ubuntu`)
3. The WAR already contains your database configuration from `WEB-INF/conf/database.conf`

#### Option B: Automatic Deployment via Tomcat Manager

Use the `deploy-war.sh` script to automatically deploy to a Tomcat server with Manager enabled:

**With username and password:**
```bash
TOMCAT_URL=http://localhost:8080 \
TOMCAT_USER=admin \
TOMCAT_PASS=password \
APP_CONTEXT=cohesive \
./deploy-war.sh
```

**With pre-encoded Basic auth header (Jenkins style):**
```bash
TOMCAT_URL=http://localhost:8080 \
TOMCAT_AUTH_HEADER="Basic YWRtaW46cGFzc3dvcmQ=" \
APP_CONTEXT=cohesive \
./deploy-war.sh
```

The script will:
- Check if the application is already deployed
- Undeploy the existing version if present
- Deploy the new WAR file
- Verify successful deployment

**Environment Variables:**
| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `TOMCAT_URL` | No | `http://localhost:8080` | Tomcat server URL |
| `TOMCAT_USER` | Yes* | - | Tomcat Manager username |
| `TOMCAT_PASS` | Yes* | - | Tomcat Manager password |
| `TOMCAT_AUTH_HEADER` | Yes* | - | Pre-encoded `Basic` auth header |
| `APP_CONTEXT` | No | `cohesive` | Application context path |

*Either `TOMCAT_USER`+`TOMCAT_PASS` OR `TOMCAT_AUTH_HEADER` must be provided.

### External Resources Dependency

The COHESIVE application requires external JavaScript libraries that are **hardcoded to load from `/res/js/*`** in the compiled HTML. These resources are provided by the [cohesive-common-resources](https://github.com/genpat-it/cohesive-common-resources) application.

**How it works:**
- The WAR file contains hardcoded references like `<script src="/res/js/hotkeys-3.10.0.min.js"></script>`
- These requests will go to `http://your-server/res/js/*` (same server as the WAR)
- You need to ensure `/res/*` requests are served by the cohesive-common-resources application

**Deployment options:**

1. **Same Tomcat server** - Deploy both WARs on the same Tomcat instance:
   ```
   webapps/
   ├── cohesive.war          → http://your-server/cohesive/
   └── res.war               → http://your-server/res/
   ```

2. **Different servers with reverse proxy** - Use Nginx to route `/res/*` requests:
   ```nginx
   location /cohesive/ {
       proxy_pass http://tomcat-server:8080/cohesive/;
   }

   location /res/ {
       proxy_pass http://resources-server:8080/res/;
   }
   ```

3. **Different servers with redirect** - Configure your web server to redirect `/res/` to another domain.

**Important:** The `/res/` path is **hardcoded in the WAR** and cannot be changed without recompiling the source code.

See [cohesive-common-resources documentation](https://github.com/genpat-it/cohesive-common-resources) for details on deploying the resources application.

## Build Configuration

### Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `GIT_REPO` | CMDBuild source repository URL | `https://github.com/genpat-it/cohesive-cmdbuild` |
| `GIT_BRANCH` | Branch to build from | `main` |

### Optional Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GIT_TOKEN` | _(empty)_ | Authentication token for private repos |
| `GIT_COMMIT` | _(empty)_ | Specific commit hash to checkout (omit for branch HEAD) |
| `MAVEN_THREADS` | `128` | Maven parallel build threads |

### Build Examples

#### Standard build
```bash
GIT_REPO=https://github.com/genpat-it/cohesive-cmdbuild \
GIT_BRANCH=main \
./build-war.sh
```

#### Build with private repository token
```bash
GIT_REPO=https://github.com/genpat-it/cohesive-cmdbuild \
GIT_BRANCH=main \
GIT_TOKEN=your_token_here \
./build-war.sh
```

#### Build from a specific commit
```bash
GIT_REPO=https://github.com/genpat-it/cohesive-cmdbuild \
GIT_BRANCH=main \
GIT_COMMIT=a1b2c3d \
./build-war.sh
```

> **Note:** When `GIT_COMMIT` is set, the full branch history is cloned (no `--depth 1`) so the commit can be checked out. When omitted, a shallow clone is used for faster builds.

#### Single-threaded build (for debugging)
```bash
GIT_REPO=https://github.com/genpat-it/cohesive-cmdbuild \
GIT_BRANCH=main \
MAVEN_THREADS=1 \
./build-war.sh
```

## Project Structure

```
cohesive-cmdbuild-builder/
├── Dockerfile                 # Builds the WAR from source
├── build-war.sh              # Build script
├── deploy-war.sh             # Automatic deployment script (optional)
├── WEB-INF/                  # Template files included in WAR
│   ├── web.xml               # Tomcat servlet configuration
│   ├── conf/                 # CMDBuild configuration
│   │   └── database.conf     # **Edit with your PostgreSQL config**
│   └── sql/                  # SQL directories (empty but required)
│       ├── functions/
│       └── patches/
├── output/                   # Build output directory
│   └── cohesive-*.war        # Final WAR file
└── README.md                 # This file
```

## Architecture

### Build Phase
```
Source Code (Git: configurable repo + branch)
    ↓
Maven Build (Java compilation)
    ↓
Sencha Cmd Build (UI compilation)
    ↓
Add WEB-INF structure (web.xml, conf/, sql/)
    ↓
Include database.conf from WEB-INF/conf/
    ↓
Package → cohesive WAR in output/
```

## Build Requirements

- **Docker** 20.10+ with BuildKit enabled (enabled by default in Docker 23.0+)
- **Disk Space**: ~2-3GB free
- **Build Time**: ~7-8 minutes (first build), ~5-6 minutes (subsequent builds with cache)
- **Network**: Access to source repository and Maven Central
- **CPU**: More cores = faster builds (128 parallel Maven threads by default)

## Troubleshooting

### Build fails with "No space left on device"

```bash
# Clean Docker cache
docker system prune -af --volumes
```

### Build fails with Git authentication error

```bash
# Provide a Git token for private repositories
GIT_REPO=https://... \
GIT_BRANCH=main \
GIT_TOKEN=your_token_here \
./build-war.sh
```

### WAR is missing SQL directories

This should not happen with the cohesive builder. If it does:
```bash
# Verify Dockerfile includes this line:
grep "cp -r /tmp/webinf-template/sql" Dockerfile
```
Should show: `cp -r /tmp/webinf-template/sql /tmp/war/WEB-INF/`

### Application fails with "IllegalArgumentException in SqlFunctionUtils"

The WAR is missing `WEB-INF/sql/{functions,patches}` directories.
**Solution**: Rebuild the WAR with the latest Dockerfile.

### CMDBuild fails with "invalid OS user detected: ROOT user not allowed"

CMDBuild 3.4.3+ requires non-root user for security.
**Solution**: Run Tomcat as `tomcat`, `ubuntu`, or any non-root user (UID > 0).

### Database connection refused

Check your `WEB-INF/conf/database.conf` and ensure the database host, port, username and password are correct before building the WAR.

### Build fails with Maven/Sencha errors

Try single-threaded build for better error visibility:
```bash
MAVEN_THREADS=1 GIT_REPO=... GIT_BRANCH=... ./build-war.sh
```

## Advanced Usage

### CI/CD Integration (Jenkins)

You can integrate the build and deployment process into Jenkins:

```groovy
pipeline {
    agent any

    parameters {
        string(name: 'GIT_REPO', defaultValue: 'https://github.com/genpat-it/cohesive-cmdbuild', description: 'CMDBuild repository')
        string(name: 'GIT_BRANCH', defaultValue: 'main', description: 'Branch to build')
        string(name: 'TOMCAT_URL', defaultValue: 'http://tomcat-server:8080', description: 'Tomcat Manager URL')
        string(name: 'APP_CONTEXT', defaultValue: 'cohesive', description: 'Application context path')
    }

    stages {
        stage('Build WAR') {
            steps {
                sh """
                    GIT_REPO=${params.GIT_REPO} \
                    GIT_BRANCH=${params.GIT_BRANCH} \
                    ./build-war.sh
                """
            }
        }

        stage('Deploy') {
            steps {
                withCredentials([string(credentialsId: 'TOMCAT_MANAGER_AUTH', variable: 'MANAGER_AUTH')]) {
                    sh """
                        TOMCAT_URL=${params.TOMCAT_URL} \
                        TOMCAT_AUTH_HEADER="Basic \${MANAGER_AUTH}" \
                        APP_CONTEXT=${params.APP_CONTEXT} \
                        ./deploy-war.sh
                    """
                }
            }
        }
    }
}
```

**Note:** Store the Base64-encoded credentials in Jenkins as a Secret Text credential with ID `TOMCAT_MANAGER_AUTH`.

To generate the Base64 credential:
```bash
echo -n "username:password" | base64
```

### Testing with a Local Database

If you want to test COHESIVE with a local PostgreSQL database:

1. **Set up PostgreSQL** (if not already installed):
   ```bash
   # Install PostgreSQL 13 or higher
   sudo apt-get install postgresql-13
   ```

2. **Create database and restore your dump**:
   ```bash
   # Create database
   sudo -u postgres createdb cohesive

   # Restore your dump
   sudo -u postgres psql cohesive < your_dump.sql
   ```

3. **Configure database connection** in `WEB-INF/conf/database.conf`:
   ```properties
   db.url=jdbc:postgresql://localhost:5432/cmdbuild
   db.username=postgres
   db.password=postgres
   ```

4. **Build the WAR** - The configuration will be included automatically
   ```bash
   GIT_REPO=https://github.com/genpat-it/cohesive-cmdbuild \
   GIT_BRANCH=main \
   ./build-war.sh
   ```

5. **Deploy to Tomcat** - Copy the generated `cohesive-*.war` to your Tomcat `webapps/` directory

### Custom Configuration

The WAR includes minimal configuration files in `WEB-INF/`:
- `web.xml` - Tomcat servlet configuration (pre-configured)
- `conf/database.conf` - **Edit this** with your PostgreSQL connection details

All configuration files are automatically included in the WAR during build.

### Build Caching & Performance

The build system uses **Docker BuildKit cache mounts** for maximum performance:

#### BuildKit Cache Optimizations

The Dockerfile is optimized with BuildKit cache mounts for:

1. **Maven dependencies** (`/root/.m2`)
   - Dependencies are cached across builds
   - Shared between containers with `sharing=locked`
   - Survives container removal

2. **APT packages** (`/var/cache/apt`, `/var/lib/apt`)
   - System packages are cached
   - Faster dependency installation

3. **Downloaded files** (`/tmp/cache`)
   - Sencha Cmd installer cached
   - libssl package cached

#### Performance Benefits

- **First build**: ~7-8 minutes (with 128 Maven threads)
- **Subsequent builds**: ~5-6 minutes (cache hits)
- **Clean rebuild**: Use `docker builder prune` to clear cache

#### Cache Management

View cache usage:
```bash
docker buildx du
```

Clear build cache:
```bash
docker builder prune -af
```

Clear specific cache:
```bash
# Clear only Maven cache
docker builder prune --filter type=exec.cachemount
```

#### Legacy: Docker Volume Cache (Not Recommended)

The old volume-based caching is **no longer needed** thanks to BuildKit. The following approach is deprecated:

<details>
<summary>Old volume-based approach (click to expand)</summary>

```bash
# OLD METHOD - Not recommended
docker volume create maven-repo
docker build -v maven-repo:/root/.m2 ...
```

BuildKit cache mounts are superior because they:
- Don't require manual volume management
- Work automatically with `--mount=type=cache`
- Are cleaned up with `docker builder prune`
</details>

## Why Use This Builder?

This builder provides:
1. **Complete WAR** → All configurations included
2. **Pre-configured** → Edit database.conf before build
3. **Reproducible** → Same inputs = same output
4. **Simple** → One command to build

## Security Considerations

- ⚠️ **Never commit** real database credentials to version control
- ⚠️ **Never commit** Git tokens in build scripts
- ⚠️ Use **environment variables** for sensitive data
- ✅ Run Tomcat as **non-root user** (CMDBuild requirement)
- ✅ Use **HTTPS** in production deployments

## Contributing

We welcome contributions! To contribute:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Test builds with different repositories and branches
- Document new features in README
- Maintain backward compatibility
- Follow existing code style

## FAQ

**Q: Can I build from any CMDBuild repository?**
A: Yes! Just set `GIT_REPO` and `GIT_BRANCH` to point to your source.

**Q: Do I need to modify the Dockerfile for my project?**
A: No. Use environment variables (`GIT_REPO`, `GIT_BRANCH`, etc.) to configure.

**Q: What CMDBuild versions are supported?**
A: Currently tested with CMDBuild 3.4.3. May work with other 3.x versions.

**Q: Can I use this for production deployments?**
A: Yes! The cohesive WAR is production-ready. Just configure your database properly.

**Q: How do I update to a new version?**
A: Change `GIT_BRANCH` to the new version branch and rebuild.

## License

This build system is provided as-is for CMDBuild deployment automation.

CMDBuild itself is licensed under AGPL v3.

## Credits

- **CMDBuild**: https://www.cmdbuild.org/
- **GenPat Project**: https://github.com/genpat-it
- **Sencha Cmd**: Required for ExtJS UI compilation
- **Contributors**: See GitHub contributors

## Support

For issues, questions, or suggestions:
- Open an issue on [GitHub](https://github.com/genpat-it/cohesive-cmdbuild-builder/issues)
- Check existing issues and documentation
- Provide detailed information (build logs, environment, steps to reproduce)

---

**Built with ❤️ by the COHESIVE Team**

*Making COHESIVE deployment simple, reliable, and reproducible.*
