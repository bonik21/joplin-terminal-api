[ English ](README.md) | [ 한국어 ]

# Joplin Terminal REST API (Docker)

리눅스용 Joplin Terminal App을 기반으로 외부에서 접속 가능한 **Joplin REST API(Web Clipper API)** 서비스 및 HTTP Gateway를 제공하는 경량 Docker 이미지입니다.

---

## 📌 배경 및 프로젝트 목적

Joplin Terminal App에는 자체 Web Clipper 및 REST API를 구동할 수 있는 기능(`joplin server start`)이 내장되어 있습니다.  
그러나 내장 서버의 바인딩 주소가 **`127.0.0.1:41184`로 하드코딩**되어 있어 컨테이너 외부나 다른 네트워크 호스트에서 직접 접근할 수 없는 제약이 있습니다. 또한 Joplin의 기본 Data API는 쿼리 파라미터(`?token=...`) 인증만 지원하며, 외부에서 즉시 원격 동기화(sync)를 호출할 수 있는 엔드포인트를 제공하지 않습니다.

이 프로젝트는 다음 방식을 통해 이러한 한계를 깔끔하게 해결합니다:
1. **Alpine Linux 기반 경량화**: 불필요한 npm 캐시, 타입 정의, 빌드 부산물을 제거한 초경량 멀티스테이지 컨테이너 환경 구축
2. **HTTP 게이트웨이 (`socat` + `gateway.sh`)**: 외부 `0.0.0.0:41185` 요청을 수신하여 표준 `Authorization: Bearer <token>` 헤더를 검증하고, 내부 루프백 `127.0.0.1:41184` Data API로 안전하게 중계
3. **온디맨드 동기화 API (`POST /sync`)**: 외부 자동화 봇, 웹훅 등에서 컨테이너 셸에 직접 들어가지 않고도 원격 동기화를 즉시 트리거 가능
4. **동시 동기화 방지(Sync Lock)**: 백그라운드 주기적 동기화와 API 트리거 동기화가 동일한 단일 파일 락(`flock`)을 공유하여 충돌을 방지하며, 이미 동기화 진행 중일 경우 `409 Conflict` 응답 반환
5. **환경 변수 자동 설정**: `.env`에 정의된 `JOPLIN_*` 환경 변수를 `settings.json`으로 자동 반영
6. **백그라운드 자동 동기화**: 설정된 주기마다 백그라운드 동기화 데몬(`joplin sync`) 자동 실행

---

## 🏗️ 아키텍처 구조

```text
[ 외부 클라이언트 / 웹훅 / 웹앱 / 자동화 봇 ]
                             │
                             ▼ HTTP Request (포트 41185)
┌────────────────────────────────────────────────────────────────────────┐
│ Docker Container (joplin-terminal-api)                                 │
│                                                                        │
│   socat + gateway.sh (0.0.0.0:41185)                                   │
│     │                                                                  │
│     ├─── POST /sync (Authorization: Bearer <token>)                    │
│     │      │                                                           │
│     │      ▼ (공유 Sync Lock 획득)                                      │
│     │    joplin sync  ──► 200 OK (동시 실행 시 409 Conflict)            │
│     │                                                                  │
│     ├─── GET /ping (공개 헬스체크)                                      │
│     │      │                                                           │
│     │      ▼ (인증 없이 직접 중계)                                      │
│     │    Joplin Web Clipper Server (127.0.0.1:41184/ping)              │
│     │                                                                  │
│     └─── 기타 Data API (/notes, /folders, /tags 등)                    │
│            │ (Authorization: Bearer <token> ➔ ?token=<token> 변환)     │
│            ▼                                                           │
│          Joplin Web Clipper Server (127.0.0.1:41184)                   │
│            │                                                           │
│            ▼                                                           │
│          Joplin Data (/root/.config/joplin)                            │
│            │                                                           │
│   Sync Daemon (공유 sync lock 기반 백그라운드 주기적 동기화)            │
└────────────────────────────────────────────────────────────────────────┘
                             │
                             ▼ (설정한 동기화 주기 또는 API 호출 시)
[ Joplin Server / Nextcloud / WebDAV / OneDrive / Dropbox / S3 ]
```

---

## 🚀 빠른 시작 (설치 방법)

### 1. 사전 요구사항
- [Docker](https://docs.docker.com/get-docker/) 및 [Docker Compose](https://docs.docker.com/compose/) 설치

### 2. 저장소 클론 및 환경 설정

```bash
# 저장소 복제 (또는 작업 디렉토리 생성)
git clone https://github.com/bonik21/joplin-terminal-api.git
cd joplin-terminal-api

# 환경 설정 파일 복사 (한국어 주석 템플릿 사용 시 .env-example.ko 복사)
cp .env-example.ko .env
# 또는 기본 템플릿 복사: cp .env-example .env
```

### 3. `.env` 파일 편집

`.env` 파일을 열어 본인의 Joplin 동기화 환경에 맞게 수정합니다.

```ini
# 원하는 Joplin 버전 (기본값: 3.7.1)
JOPLIN_VERSION=3.7.1

# 로케일 및 시간 포맷
JOPLIN_locale=ko
JOPLIN_dateFormat=YYYY-MM-DD
JOPLIN_timeFormat=HH:mm

# ==============================================================================
# Joplin Sync Target (동기화 대상)
# 0: None, 2: File system, 3: OneDrive, 5: Nextcloud, 6: WebDAV,
# 7: Dropbox, 8: S3, 9: Joplin Server, 10: Joplin Cloud, 11: Joplin Server (SAML)
# ==============================================================================
JOPLIN_sync_target=9
JOPLIN_sync_9_path=https://your-joplin-server.com
JOPLIN_sync_9_username=your_username
JOPLIN_sync_9_password=your_password

# 동기화 주기 (초 단위, 기본 최소 300초)
JOPLIN_sync_interval=300
```

> **Tip (환경 변수 작성 규칙 및 주의사항):**  
> - config에서 지정 가능한 전체 옵션은 [Joplin Terminal 공식 문서](https://joplinapp.org/help/apps/terminal/#commands)의 config 부분을 참고하세요.  
> - `JOPLIN_` 뒤에 오는 언더스코어(`_`)는 `settings.json`의 점(`.`)으로 자동 치환되며, **카멜케이스(대소문자)는 반드시 유지**해야 합니다.  
>   - 예: `JOPLIN_dateFormat=YYYY-MM-DD` ➔ `"dateFormat": "YYYY-MM-DD"`  
>   - 예: `JOPLIN_sync_target=9` ➔ `"sync.target": 9`  
>   - 예: `JOPLIN_sync_9_path=...` ➔ `"sync.9.path": "..."`  
> - **한국어 로케일 주의**: `ko_KR`이 아닌 `ko`로 설정해야 정상 인식됩니다. (예: `JOPLIN_locale=ko`)

### 4. 컨테이너 빌드 및 실행

```bash
docker compose up -d --build
```

실행 상태 및 로그를 확인합니다:
```bash
docker compose logs -f
```

### 5. 최초 1회 수동 동기화 실행 (필수)

컨테이너 최초 실행 시에는 로컬 데이터베이스에 아이템이 전혀 없는 상태(`total: 0`)입니다. 잘못된 덮어쓰기나 예기치 않은 데이터 유실을 방지하기 위해 컨테이너 내부의 자동 동기화 루프는 일시정지(`[sync] Local database is empty. Synchronization paused...`) 상태로 대기합니다.

따라서 최초 1회는 사용자가 직접 설정 및 상태를 확인한 후 수동으로 동기화를 시작해주어야 합니다.

```bash
# 1) 현재 Joplin 설정값 확인
docker compose exec joplin-terminal-api joplin config

# 2) 동기화 상태 확인
docker compose exec joplin-terminal-api joplin status

# 3) 최초 수동 동기화 실행
docker compose exec joplin-terminal-api joplin sync
```

최초 동기화가 성공하여 로컬 데이터가 채워지면(`Item count > 0`), 이후부터는 백그라운드 데몬이 설정된 동기화 주기(`JOPLIN_sync_interval`)에 맞춰 자동으로 동기화를 지속합니다. 또한 필요할 때 언제든지 `POST /sync` API를 호출하여 동기화할 수 있습니다.

---

## 🔑 API 토큰 확인 및 사용법

Joplin REST API 및 게이트웨이를 호출하려면 보안 토큰(`api.token`)이 필요합니다.

### 1. API 토큰 확인하기

컨테이너가 실행된 후 아래 명령어로 토큰을 확인합니다:

```bash
cat joplin-data/settings.json
```

또는 볼륨 파일에서 직접 추출:
```bash
# jq가 설치되어 있는 경우
jq -r '."api.token"' ./joplin-data/settings.json
```

출력 예시:
```text
a1b2c3d4e5f6... (64자리 토큰)
```

이 토큰을 HTTP 요청 시 `Authorization: Bearer <토큰>` 헤더로 전송합니다.

### 2. API 호출 테스트

호스트 또는 외부에서 `41185` 포트로 요청을 전송합니다:

#### 헬스체크 (`/ping`)
공개 헬스체크 엔드포인트입니다. 별도의 인증 토큰이 필요하지 않습니다.
```bash
curl http://localhost:41185/ping
```
- **응답**: `200 OK` (`JoplinClipperServer`)

#### 동기화 즉시 실행 (`POST /sync`)
공유 락 제어 하에 `joplin sync`를 즉시 실행합니다.
```bash
curl -X POST http://localhost:41185/sync \
  -H "Authorization: Bearer <YOUR_API_TOKEN>"
```
- **응답 코드 안내**:
  - `200 OK`: `Sync completed` (동기화 정상 완료)
  - `409 Conflict`: `Sync already running` (백그라운드 동기화 또는 다른 API 요청이 이미 동기화 중임)
  - `401 Unauthorized`: `Unauthorized` (토큰 누락 또는 유효하지 않음)
  - `405 Method Not Allowed`: `Method Not Allowed` (GET 등 비-POST 요청 시 거부)
  - `500 Internal Server Error`: `Sync failed` (Joplin 동기화 도중 오류 발생)

#### 루트 폴더(노트북) 목록 조회
```bash
curl http://localhost:41185/folders \
  -H "Authorization: Bearer <YOUR_API_TOKEN>"
```

#### 노트 목록 조회 (쿼리 파라미터 지원)
기존 Data API의 쿼리 파라미터가 그대로 유지됩니다:
```bash
curl "http://localhost:41185/notes?fields=id,title,updated_time&limit=10" \
  -H "Authorization: Bearer <YOUR_API_TOKEN>"
```

#### 새 노트 생성
```bash
curl -X POST http://localhost:41185/notes \
  -H "Authorization: Bearer <YOUR_API_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"title": "Docker API 테스트", "body": "Joplin Terminal API Gateway가 정상 동작합니다!"}'
```

자세한 API 명세는 [Joplin Data API 공식 문서](https://joplinapp.org/help/api/references/rest_api)를 참고하세요.

---

## ⚙️ 포트 및 보안 세부사항

- **포트 `41185` (Gateway)**: 외부에 공개되는 유일한 게이트웨이 포트입니다. HTTP 요청을 수신하여 `Authorization: Bearer` 인증 검증 및 동기화 락 제어를 수행하고, 검증된 요청만 내부로 전달합니다.
- **포트 `41184` (내부 루프백)**: Joplin Terminal 내부 Web Clipper 서버 포트(`127.0.0.1:41184`)로, 컨테이너 외부에는 일절 노출되지 않습니다.
- **OneDrive 동기화 사용 시**: OneDrive를 동기화 대상으로 사용하는 경우, 최초 로그인 OAuth 인증 리디렉션을 위해 `docker-compose.yml`에서 `9967` 포트의 주석을 해제해야 합니다:
  ```yaml
  ports:
    - "41185:41185"
    - "9967:9967"  # OneDrive OAuth 인증용 포트
  ```

### Joplin Terminal App 버전 확인 및 업데이트 안내
컨테이너가 시작될 때 최신 Joplin Terminal App 버전을 자동으로 확인합니다.  
새로운 버전이 있을 경우 컨테이너 로그에 다음과 같은 알림이 출력됩니다:

```text
--------------------------------------------------
 [NOTICE] A new Joplin version (vx.y.z) is available!
 Current running version: va.b.c

 To upgrade:
   1. Update 'JOPLIN_VERSION=x.y.z' in your .env file
   2. Rebuild the container: docker compose up -d --build
--------------------------------------------------
```

알림이 뜨면 안내에 따라 `.env` 파일의 `JOPLIN_VERSION` 값을 새 버전으로 수정한 후, `docker compose up -d --build`를 실행하여 새 버전으로 컨테이너를 다시 빌드하시면 됩니다.

---

## 📂 볼륨 영속성

- `./joplin-data`: 컨테이너 내부의 `/root/.config/joplin` 경로에 마운트됩니다.
  - SQLite 데이터베이스 (`database.sqlite`)
  - 설정 파일 (`settings.json`)
  - 리소스/첨부파일 (`resources/`)
- 컨테이너가 재생성되거나 업데이트되어도 데이터는 호스트에 안전하게 보존됩니다.

---

## 📄 라이선스

이 프로젝트는 MIT 라이선스를 따릅니다. Joplin 자체의 라이선스는 [Joplin 공식 리포지토리](https://github.com/laurent22/joplin)를 참조하세요.
