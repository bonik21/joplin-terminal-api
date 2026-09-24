[ English ] | [ 한국어 ](README.ko.md)

# Joplin Terminal REST API (Docker)

A lightweight Docker image providing an externally accessible **Joplin REST API (Web Clipper API)** service and HTTP Gateway powered by the official Joplin Terminal App on Linux.

---

## 📌 Background & Motivation

The Joplin Terminal App comes with a built-in Web Clipper and REST API server (`joplin server start`).  
However, the internal server's listening host is **hardcoded to `127.0.0.1:41184`**, making it impossible to access directly from outside the container or other network hosts. Furthermore, Joplin's internal Data API requires passing the authentication token as a query parameter (`?token=...`) and does not natively expose an endpoint to trigger remote synchronization on demand.

This project cleanly overcomes these limitations with:
1. **Lightweight Alpine Base**: An ultra-compact multi-stage build removing unnecessary npm caches, typings, and build artifacts.
2. **HTTP Gateway (`socat` + `gateway.sh`)**: Exposes external port `41185`, accepts standard `Authorization: Bearer <token>` headers, and securely bridges traffic to Joplin's internal `127.0.0.1:41184` Data API.
3. **On-Demand Synchronization (`POST /sync`)**: Allows external automation tools and webhooks to trigger synchronization without accessing the container shell.
4. **Mutual Exclusion Sync Lock**: Synchronizes background scheduled runs and on-demand API triggers via a shared file lock, preventing concurrent sync collisions and returning `409 Conflict` if a sync is already active.
5. **Automated Configuration via `.env`**: Automatically transforms `JOPLIN_*` environment variables into `settings.json` upon startup.
6. **Automated Background Sync**: Runs an automatic background sync daemon (`joplin sync`) on configurable intervals.

---

## 🏗️ Architecture

```text
[ External Clients / Webhooks / Web Apps / Automation Bots ]
                             │
                             ▼ HTTP Request (Port 41185)
┌────────────────────────────────────────────────────────────────────────┐
│ Docker Container (joplin-terminal-api)                                 │
│                                                                        │
│   socat + gateway.sh (0.0.0.0:41185)                                   │
│     │                                                                  │
│     ├─── POST /sync (Authorization: Bearer <token>)                    │
│     │      │                                                           │
│     │      ▼ (Acquires Shared Sync Lock)                               │
│     │    joplin sync  ──► 200 OK (or 409 Conflict if already running)  │
│     │                                                                  │
│     ├─── GET /ping (Public Health Check)                               │
│     │      │                                                           │
│     │      ▼ (Forwards directly without auth)                          │
│     │    Joplin Web Clipper Server (127.0.0.1:41184/ping)              │
│     │                                                                  │
│     └─── Data API (/notes, /folders, /tags, etc.)                      │
│            │ (Authorization: Bearer <token> ➔ ?token=<token>)          │
│            ▼                                                           │
│          Joplin Web Clipper Server (127.0.0.1:41184)                   │
│            │                                                           │
│            ▼                                                           │
│          Joplin Data (/root/.config/joplin)                            │
│            │                                                           │
│   Sync Daemon (Periodic background loop via shared sync lock)          │
└────────────────────────────────────────────────────────────────────────┘
                             │
                             ▼ (At defined sync intervals or API trigger)
[ Joplin Server / Nextcloud / WebDAV / OneDrive / Dropbox / S3 ]
```

---

## 🚀 Distribution Images & Tagging Policy

Pre-built Docker images are automatically published to Docker Hub (`bonik21/joplin-terminal-api`). You can use the container directly without cloning the repository or building from source.

- **Docker image tag = `joplin-terminal-app` version**. Users only need to select their desired Joplin version.
- The HTTP Gateway (`joplin-terminal-api`) defaults to the stable `main` branch. For testing the latest development features, use tags ending with `-dev`.

| Image Tag | Joplin Version | Joplin Terminal API Version | Description |
|---|---|---|---|
| `bonik21/joplin-terminal-api:latest` | Latest release | `main` | **[Recommended]** Latest Joplin + stable API gateway |
| `bonik21/joplin-terminal-api:<version>` (e.g. `3.7.1`) | Specified version (`3.7.1`) | `main` | Fixed Joplin version + stable API gateway |
| `bonik21/joplin-terminal-api:dev` | Latest release | `dev` | Latest Joplin + development API gateway |
| `bonik21/joplin-terminal-api:<version>-dev` (e.g. `3.7.1-dev`) | Specified version (`3.7.1`) | `dev` | Fixed Joplin version + development API gateway |

---

## 🚀 Quick Start (Installation)

### 1. Prerequisites
- [Docker](https://docs.docker.com/get-docker/) & [Docker Compose](https://docs.docker.com/compose/) installed

### 2. Directory & Configuration Setup

You do not need to clone the full repository. Simply prepare a `docker-compose.yml` and `.env` file in your workspace directory:

```bash
mkdir joplin-api && cd joplin-api
```

#### Create `docker-compose.yml`
```yaml
services:
  joplin-terminal-api:
    image: bonik21/joplin-terminal-api:latest
    container_name: joplin-terminal-api
    restart: unless-stopped
    ports:
      - "41185:41185"
      # [Optional] Uncomment if you use OneDrive as sync target (OAuth redirect port)
      # - "9967:9967"
    env_file:
      - .env
    volumes:
      - ./joplin-data:/root/.config/joplin
```

### 3. Create & Configure `.env` File

Create a `.env` file for your Joplin sync configuration (`JOPLIN_VERSION` is managed via the Docker image tag, so it is no longer required in `.env`):

```ini
# Locale and Date/Time format
JOPLIN_locale=en_GB
JOPLIN_dateFormat=DD/MM/YYYY
JOPLIN_timeFormat=HH:mm

# ==============================================================================
# Joplin Sync Target Options
# 0: None, 2: File system, 3: OneDrive, 5: Nextcloud, 6: WebDAV,
# 7: Dropbox, 8: S3, 9: Joplin Server, 10: Joplin Cloud, 11: Joplin Server (SAML)
# ==============================================================================
JOPLIN_sync_target=9
JOPLIN_sync_9_path=https://your-joplin-server.com
JOPLIN_sync_9_username=your_username
JOPLIN_sync_9_password=your_password

# Sync interval in seconds (Default minimum: 300)
JOPLIN_sync_interval=300
```

> **Tip (Configuration Rules & Notes):**  
> - For all available configuration options, refer to the [official Joplin Terminal documentation](https://joplinapp.org/help/apps/terminal/#commands).  
> - Any variable prefixing `JOPLIN_` will replace underscores (`_`) with dots (`.`) in `settings.json`. **CamelCase must be preserved**:  
>   - E.g. `JOPLIN_dateFormat=YYYY-MM-DD` ➔ `"dateFormat": "YYYY-MM-DD"`  
>   - E.g. `JOPLIN_sync_target=9` ➔ `"sync.target": 9`  
>   - E.g. `JOPLIN_sync_9_path=...` ➔ `"sync.9.path": "..."`  
> - **Korean Locale Note**: Use `ko` instead of `ko_KR` (e.g. `JOPLIN_locale=ko`).

### 4. Run the Container

Run the container using Docker Compose (Docker will automatically pull the image):

```bash
docker compose up -d
```

View startup logs:
```bash
docker compose logs -f
```

### 5. Initial Manual Synchronization (Required)

Upon first run, the local database contains no items (`total: 0`). To prevent unexpected data loss or overwriting, the automatic background synchronization loop enters a paused state (`[sync] Local database is empty. Synchronization paused...`).

Therefore, you must check the configuration and trigger an initial sync manually:

```bash
# 1) Verify Joplin configurations
docker compose exec joplin-terminal-api joplin config

# 2) Check synchronization status
docker compose exec joplin-terminal-api joplin status

# 3) Trigger initial synchronization
docker compose exec joplin-terminal-api joplin sync
```

Once the initial synchronization finishes and items exist locally (`Item count > 0`), the background daemon will automatically keep synchronizing at your configured interval (`JOPLIN_sync_interval`). You can also trigger a sync at any time via the `POST /sync` API.

---

## 🔑 Retrieving the API Token & Usage

Accessing the Joplin REST API and Gateway requires an authentication token (`api.token`).

### 1. Retrieve the API Token

Once the container is started, retrieve your token using:

```bash
cat joplin-data/settings.json
```

Or extract it with `jq`:
```bash
jq -r '."api.token"' ./joplin-data/settings.json
```

Example output:
```text
a1b2c3d4e5f6... (64-character token)
```

Use this value as your Bearer token in the `Authorization` header:
```http
Authorization: Bearer a1b2c3d4e5f6...
```

### 2. API Endpoints & Testing

Send HTTP requests to port `41185` on your host:

> **Tip (`127.0.0.1` vs `localhost`):**  
> We recommend using `127.0.0.1` instead of `localhost`. Depending on host OS and Docker network configuration, `localhost` may resolve first to IPv6 (`::1`), leading to `Connection refused` if the container port is bound only to IPv4 (`0.0.0.0`).

#### Health Check (`/ping`)
Public healthcheck endpoint. Does not require authentication.
```bash
curl http://127.0.0.1:41185/ping
```
- **Response**: `200 OK` (`JoplinClipperServer`)

#### Trigger Synchronization (`POST /sync`)
Triggers an immediate `joplin sync` execution safely governed by the shared lock.
```bash
curl -X POST http://127.0.0.1:41185/sync \
  -H "Authorization: Bearer <YOUR_API_TOKEN>"
```
- **Responses**:
  - `200 OK`: `Sync completed` (synchronization finished successfully)
  - `409 Conflict`: `Sync already running` (background sync or another API request is currently running)
  - `401 Unauthorized`: `Unauthorized` (missing or invalid Bearer token)
  - `405 Method Not Allowed`: `Method Not Allowed` (non-POST methods such as `GET` are rejected)
  - `500 Internal Server Error`: `Sync failed` (Joplin sync returned an error)

#### List Folders (Notebooks)
```bash
curl http://127.0.0.1:41185/folders \
  -H "Authorization: Bearer <YOUR_API_TOKEN>"
```

#### List Notes (with Query Parameters)
Existing query parameters are fully preserved (specify `body` in `?fields=` to fetch note contents):
```bash
curl "http://127.0.0.1:41185/notes?fields=id,title,body,updated_time&limit=10" \
  -H "Authorization: Bearer <YOUR_API_TOKEN>"
```

#### Create a New Note
```bash
curl -X POST http://127.0.0.1:41185/notes \
  -H "Authorization: Bearer <YOUR_API_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"title": "Docker API Test", "body": "Joplin Terminal API Gateway is working properly!"}'
```

For full Joplin Data API specifications, see the [Joplin Data API Official Documentation](https://joplinapp.org/help/api/references/rest_api).

---

## ⚙️ Port & Security Details

- **Port `41185` (Gateway)**: The only port published to external networks. It terminates incoming HTTP requests, enforces Bearer token authentication, manages sync locks, and forwards validated requests.
- **Port `41184` (Internal Loopback)**: Joplin Terminal's internal Web Clipper server listens strictly on `127.0.0.1:41184`. It is not published outside the container.
- **When Using OneDrive Sync**: If you use OneDrive as your sync target, expose port `9967` in `docker-compose.yml` for OAuth redirect during initial authorization:
  ```yaml
  ports:
    - "41185:41185"
    - "9967:9967"  # Port for OneDrive OAuth redirection
  ```

### Version Notification & Upgrade Guide
The container checks for the latest Joplin release upon startup. If a newer release is found, a notice is displayed in the container logs:

```text
--------------------------------------------------
 [NOTICE] A new Joplin version (vx.y.z) is available!
 Current running version: va.b.c

 To upgrade:
   Update image tag in docker-compose.yml or pull the latest image:
   docker compose pull && docker compose up -d
--------------------------------------------------
```

When notified, simply update the image tag in your `docker-compose.yml` file (or pull the updated `latest` image) and restart the container:
```bash
docker compose pull && docker compose up -d
```

---

## 📂 Volume Persistence

- `./joplin-data`: Mounted to `/root/.config/joplin` inside the container.
  - SQLite database (`database.sqlite`)
  - Settings file (`settings.json`)
  - Resource attachments (`resources/`)
- All data remains safely stored on the host across container recreations and upgrades.

---

## 📄 License

This project is licensed under the MIT License. For Joplin's own license, please visit the [official Joplin repository](https://github.com/laurent22/joplin).

---

- **Author**: BoniK ([mail@bonik.me](mailto:mail@bonik.me) / [https://bonik.me](https://bonik.me))
- **Support**: [Buy me a coffee](https://buymeacoffee.com/bonik)

