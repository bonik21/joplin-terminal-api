[ English ] | [ 한국어 ](README.ko.md)

# Joplin Terminal REST API (Docker)

A lightweight Docker image providing an externally accessible **Joplin REST API (Web Clipper API)** service powered by the official Joplin Terminal App on Linux.

---

## 📌 Background & Motivation

The Joplin Terminal App comes with a built-in Web Clipper and REST API server (`joplin server start`).  
However, the internal server's listening host is **hardcoded to `127.0.0.1:41184`**, making it impossible to access directly from outside the container or other network hosts.

This project cleanly overcomes this limitation by providing:
1. **Lightweight Alpine Base**: An ultra-compact multi-stage build removing unnecessary npm caches, typings, and build artifacts.
2. **Port Proxying via `socat`**: Seamlessly forwards external traffic from `0.0.0.0:41185` to local `127.0.0.1:41184`.
3. **Automated Configuration via `.env`**: Automatically transforms `JOPLIN_*` environment variables into `settings.json` upon startup.
4. **Automated Background Sync**: Runs an automatic background sync daemon (`joplin sync`) on configurable intervals.

---

## 🏗️ Architecture

```text
[ External Clients / Web Apps / Automation Bots ]
                     │
                     ▼ HTTP Request (Port 41185)
┌────────────────────────────────────────────────────────┐
│ Docker Container (joplin-terminal-api)                 │
│                                                        │
│   socat (0.0.0.0:41185)                                │
│     │                                                  │
│     ▼ (Internal Loopback Forwarding)                   │
│   Joplin Web Clipper Server (127.0.0.1:41184)          │
│     │                                                  │
│     ▼                                                  │
│   Joplin Data (/root/.config/joplin)                   │
│     │                                                  │
│   Sync Daemon (Background joplin sync)                 │
└────────────────────────────────────────────────────────┘
                     │
                     ▼ (At defined sync intervals)
[ Joplin Server / Nextcloud / WebDAV / OneDrive / Dropbox / S3 ]
```

---

## 🚀 Quick Start (Installation)

### 1. Prerequisites
- [Docker](https://docs.docker.com/get-docker/) & [Docker Compose](https://docs.docker.com/compose/) installed

### 2. Clone Repository & Set Up Environment

```bash
# Clone repository
git clone https://github.com/bonik21/joplin-terminal-api.git
cd joplin-terminal-api

# Copy environment configuration template
cp .env-example .env
# (For Korean template, copy: cp .env-example.ko .env)
```

### 3. Configure `.env` File

Edit the `.env` file to match your Joplin synchronization setup:

```ini
# Desired Joplin version (Default: 3.7.1)
JOPLIN_VERSION=3.7.1

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

### 4. Build & Run the Container

```bash
docker compose up -d --build
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

Once the initial synchronization finishes and items exist locally (`Item count > 0`), the background daemon will automatically keep synchronizing at your configured interval (`JOPLIN_sync_interval`).

---

## 🔑 Retrieving the API Token & Usage

Accessing the Joplin REST API requires an authentication token (`api.token`).

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

### 2. Test API Requests

Send HTTP requests to port `41185` on your host:

#### Health Check (`ping`)
```bash
curl http://localhost:41185/ping
```
*Response: `JoplinClipperServer`*

#### List Folders (Notebooks)
```bash
curl "http://localhost:41185/folders?token=<YOUR_API_TOKEN>"
```

#### List Notes
```bash
curl "http://localhost:41185/notes?token=<YOUR_API_TOKEN>"
```

#### Create a New Note
```bash
curl -X POST "http://localhost:41185/notes?token=<YOUR_API_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"title": "Docker API Test", "body": "Joplin Terminal API is working properly!"}'
```

For full API specifications, see the [Joplin Data API Official Documentation](https://joplinapp.org/help/api/references/rest_api).

---

## ⚙️ Additional Configuration

### When Using OneDrive Sync
If you use OneDrive as your sync target, you need to expose port `9967` in `docker-compose.yml` for OAuth redirect during initial authorization:

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
   1. Update 'JOPLIN_VERSION=x.y.z' in your .env file
   2. Rebuild the container: docker compose up -d --build
--------------------------------------------------
```

When notified, simply update `JOPLIN_VERSION` in your `.env` file and rebuild the container with `docker compose up -d --build`.

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
