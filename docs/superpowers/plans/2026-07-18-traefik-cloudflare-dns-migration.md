# Traefik Cloudflare DNS 移行 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Traefik の ACME DNS-01 チャレンジを Google Cloud DNS から Cloudflare に切り替えるための Cloudflare 版 compose / env / ドキュメントをリポジトリに追加する。

**Architecture:** 既存のプロバイダ別パターン（`compose.<provider>.yaml` + `.env.<provider>.example`）を踏襲し、`compose.gcloud.yaml` をベースに Cloudflare 版を新規追加する。CA は ZeroSSL のまま（resolver 名 `zerossl` / caserver / EAB を維持）、変更は DNS プロバイダと認証方式（GCP secrets → `CF_DNS_API_TOKEN` env）のみ。gcloud/aws 版はロールバック用に残す。

**Tech Stack:** Docker Compose, Traefik v3.6.2, ZeroSSL (ACME + EAB), Cloudflare DNS API (lego cloudflare provider), Docker Compose 環境変数補間。

## Global Constraints

- Traefik イメージは `traefik:v3.6.2` を維持（既存 aws/gcloud と同一）。
- ACME resolver 名は `zerossl` を維持。caserver `https://acme.zerossl.com/v2/DV90`、EAB（`EAB_KID` / `EAB_HMAC_KEY`）、email（`CA_EMAIL`）は変更しない。
- 対象ドメインは `local.challtech.dev`（main）+ `*.local.challtech.dev`（SANs）。各サービスの Traefik ラベルは変更しない。
- Cloudflare 認証は環境変数 `CF_DNS_API_TOKEN` のみ（Docker secrets / サービスアカウントファイルは使わない）。
- 証明書ストレージは名前付きボリューム `ssl:/zerossl`、`storage=/zerossl/acme.json` を維持。
- gcloud / aws の既存ファイルは削除しない。
- 作業ブランチ: `feat/traefik-cloudflare-dns`。
- `.env` は `.gitignore` 済み。実トークン等の秘匿値はコミットしない。

---

### Task 1: `.env.cloudflare.example` の作成

**Files:**
- Create: `/Users/seiyu/workspaces/projects/dev-container/.env.cloudflare.example`

**Interfaces:**
- Produces: 環境変数 `CA_EMAIL`, `EAB_KID`, `EAB_HMAC_KEY`, `CF_DNS_API_TOKEN` の雛形。Task 2 の `compose.cloudflare.yaml` がこれらを参照する。

- [ ] **Step 1: ベースとの差分を確認**

Run: `cat .env.gcloud.example`
Expected: GCP 用ブロック（`GCP_SERVICE_ACCOUNT_FILE` / `GCP_PROJECT_ID`）を含む雛形が表示される。この GCP ブロックを Cloudflare 用に置き換える。

- [ ] **Step 2: `.env.cloudflare.example` を作成**

以下の内容で新規作成する:

```dotenv
# 自身のemail
CA_EMAIL=
# https://zerossl.com からログインしてdeveloperにあるEAB Credentials for ACME ClientsからGenerateする
EAB_KID=
EAB_HMAC_KEY=

# Cloudflare DNS設定
# My Profile → API Tokens → Create Token → Custom token で発行する
# 必要な権限: Zone → DNS → Edit, Zone → Zone → Read
# Zone Resources は challtech.dev のみに限定する（Global API Keyは使わない）
CF_DNS_API_TOKEN=

# CoreDNSで独自の設定ファイルを使用したい場合
# CORE_FILE=./docker/dns/custom.Corefile
```

- [ ] **Step 3: 検証（GCP 変数が残っていないこと）**

Run: `grep -E 'GCP_|GCE_' .env.cloudflare.example; echo "exit=$?"`
Expected: 一致なし（`exit=1`）。`CF_DNS_API_TOKEN=` の行が存在すること（`grep CF_DNS_API_TOKEN .env.cloudflare.example` で確認）。

- [ ] **Step 4: Commit**

```bash
git add .env.cloudflare.example
git commit -m "feat: Cloudflare DNS用の.envサンプルを追加"
```

---

### Task 2: `compose.cloudflare.yaml` の作成

**Files:**
- Create: `/Users/seiyu/workspaces/projects/dev-container/compose.cloudflare.yaml`

**Interfaces:**
- Consumes: Task 1 の環境変数（`CA_EMAIL`, `EAB_KID`, `EAB_HMAC_KEY`, `CF_DNS_API_TOKEN`）。
- Produces: `docker compose -f compose.cloudflare.yaml up -d` で起動可能な Cloudflare 版 Traefik 構成。

- [ ] **Step 1: ベースとの差分を把握**

Run: `sed -n '1,53p' compose.gcloud.yaml`
Expected: 冒頭に `secrets:` ブロック、`proxy` に `secrets:` / `environment:`（`GCE_*`）/ `provider=gcloud` があることを確認。これらが Cloudflare 版での変更対象。

- [ ] **Step 2: `compose.cloudflare.yaml` を作成**

以下の内容で新規作成する（gcloud 版から `secrets` 削除・`environment` を `CF_DNS_API_TOKEN` のみに・`provider=cloudflare`・`resolvers` 追加）:

```yaml
services:
  proxy:
    image: traefik:v3.6.2
    ports:
      - "80:80"
      - "443:443"
      - "6001:6001"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ssl:/zerossl
    environment:
      CF_DNS_API_TOKEN: "${CF_DNS_API_TOKEN}"
    networks:
      default:
      web:
        ipv4_address: 192.168.100.250
    restart: always
    dns:
      - "1.1.1.1"
    command:
      - "--log.level=DEBUG"
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.forwardedHeaders.insecure=true"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.websecure.forwardedHeaders.insecure=true"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      - "--certificatesresolvers.zerossl.acme.dnschallenge=true"
      - "--certificatesresolvers.zerossl.acme.dnschallenge.provider=cloudflare"
      - "--certificatesresolvers.zerossl.acme.dnschallenge.resolvers=1.1.1.1:53,8.8.8.8:53"
      - "--certificatesresolvers.zerossl.acme.caserver=https://acme.zerossl.com/v2/DV90"
      - "--certificatesresolvers.zerossl.acme.email=${CA_EMAIL}"
      - "--certificatesresolvers.zerossl.acme.storage=/zerossl/acme.json"
      - "--certificatesresolvers.zerossl.acme.eab.kid=${EAB_KID}"
      - "--certificatesresolvers.zerossl.acme.eab.hmacEncoded=${EAB_HMAC_KEY}"
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=web"
      - "traefik.http.routers.proxy.rule=Host(`proxy.local.challtech.dev`)"
      - "traefik.http.routers.proxy.tls=true"
      - "traefik.http.routers.proxy.tls.certresolver=zerossl"
      - "traefik.http.services.proxy.loadbalancer.server.port=8080"
      - "traefik.http.routers.proxy.tls.domains[0].main=local.challtech.dev"
      - "traefik.http.routers.proxy.tls.domains[0].sans=*.local.challtech.dev"
  mysql8:
    image: mysql/mysql-server:8.0.23
    ports:
      - "${MYSQL8_PORT:-3306}:3306"
    volumes:
      - ./docker/mysql/data:/var/lib/mysql
    environment:
      MYSQL_ROOT_PASSWORD: "${DB_PASSWORD:-password}"
      MYSQL_ROOT_HOST: "%"
      MYSQL_USER: "${DB_USERNAME:-super}"
      MYSQL_PASSWORD: "${DB_PASSWORD:-password}"
      MYSQL_ALLOW_EMPTY_PASSWORD: 1
    networks:
      dev-container:
    restart: always
    command: mysqld --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci --default-authentication-plugin=mysql_native_password --sql_mode="NO_ENGINE_SUBSTITUTION"

  redis6:
    image: redis:6-alpine
    volumes:
      - redis6:/data
    ports:
      - "6379:6379"
    networks:
      dev-container:
    restart: always

  mail:
    image: axllent/mailpit
    volumes:
      - mail:/mailpitstorage
    environment:
      TZ: Asia/Tokyo
      MP_DATA_FILE: /mailpitstorage/mailpit.db
    ports:
      - "${FORWARD_MAIL_SMTP_PORT:-1025}:1025"
    networks:
      default:
      dev-container:
    restart: always
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=dev-container_default"
      - "traefik.http.routers.mail.rule=Host(`mail.local.challtech.dev`)"
      - "traefik.http.routers.mail.tls=true"
      - "traefik.http.routers.mail.tls.certresolver=zerossl"
      - "traefik.http.services.mail.loadbalancer.server.port=8025"

  minio:
    image: minio/minio:latest
    environment:
      MINIO_ROOT_USER: admin
      MINIO_ROOT_PASSWORD: password
    entrypoint: bash
    command: >
      -c "
      mkdir -p /data/.minio.sys/buckets;
      cp -r /policies/* /data/.minio.sys/;
      cp -r /export/* /data/;
      /usr/bin/docker-entrypoint.sh minio server /data --console-address :9001;
      "
    volumes:
      - ./docker/minio/data:/data
      - ./docker/minio/export:/export
      - ./docker/minio/config:/root/.minio
      - ./docker/minio/policies:/policies
    ports:
      - "9000:9000"
    expose:
      - 9001
    networks:
      default:
      dev-container:
    restart: always
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=dev-container_default"
      - "traefik.http.routers.minio.rule=Host(`minio.local.challtech.dev`)"
      - "traefik.http.routers.minio.tls=true"
      - "traefik.http.routers.minio.tls.certresolver=zerossl"
      - "traefik.http.services.minio.loadbalancer.server.port=9001"
  dns:
    image: coredns/coredns:1.11.1
    volumes:
      - "${CORE_FILE:-./docker/dns/Corefile}:/etc/coredns/Corefile"
    ports:
      - "53:53"
      - "53:53/udp"
    networks:
      default:
    profiles:
      - dns
    command: -conf /etc/coredns/Corefile

networks:
  web:
    external: true
  dev-container:
    external: true

volumes:
  redis6:
  ssl:
  mail:
```

- [ ] **Step 3: 構成の静的検証（YAML + 環境変数補間）**

Run: `CF_DNS_API_TOKEN=dummy CA_EMAIL=test@example.com EAB_KID=k EAB_HMAC_KEY=h docker compose -f compose.cloudflare.yaml config >/dev/null && echo OK`
Expected: `OK`（YAML 妥当・環境変数補間成功）。エラーが出た場合はインデント/構文を修正。

- [ ] **Step 4: 差分検証（gcloud 版との想定差分のみか）**

Run: `grep -nE 'provider=|CF_DNS_API_TOKEN|GCE_|secrets|resolvers=' compose.cloudflare.yaml`
Expected: `provider=cloudflare` と `CF_DNS_API_TOKEN` と `resolvers=1.1.1.1:53,8.8.8.8:53` が存在し、`GCE_` と `secrets` が**存在しない**こと。

- [ ] **Step 5: Commit**

```bash
git add compose.cloudflare.yaml
git commit -m "feat: Cloudflare DNS用のcompose定義を追加"
```

---

### Task 3: `README.md` に Cloudflare 手順を追加

**Files:**
- Modify: `/Users/seiyu/workspaces/projects/dev-container/README.md`

**Interfaces:**
- Consumes: Task 1 / Task 2 で追加したファイル名（`.env.cloudflare.example`, `compose.cloudflare.yaml`）。

- [ ] **Step 1: 既存構成を確認**

Run: `cat README.md`
Expected: 「AWS Route53 を使用する場合」「Google Cloud DNS を使用する場合」の環境構築セクションと起動セクションがある。ここに Cloudflare 版を同じ体裁で追記する。

- [ ] **Step 2: 環境構築セクションに追記**

`### Google Cloud DNS を使用する場合` の環境構築ブロック（`2. \`.env\`の項目を全部埋める（GCP 関連の環境変数を設定）` の行の直後）に、以下を追加する:

```markdown

### Cloudflare を使用する場合

1. `.env.cloudflare.example`をコピーして`.env`を作成する
2. `.env`の項目を全部埋める（`CF_DNS_API_TOKEN` を設定）
```

- [ ] **Step 3: 起動セクションに追記**

`#### Google Cloud DNS を使用する場合` の起動ブロック（gcloud の ```` ```sh ... docker compose -f compose.gcloud.yaml up -d ... ``` ```` コードブロックの直後）に、以下を追加する:

````markdown

#### Cloudflare を使用する場合

```sh
docker compose -f compose.cloudflare.yaml up -d
```
````

- [ ] **Step 4: 検証**

Run: `grep -c 'compose.cloudflare.yaml' README.md`
Expected: `1` 以上。`grep -c 'Cloudflare' README.md` で 2 箇所（環境構築・起動）追記されていること。

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: READMEにCloudflare利用手順を追加"
```

---

### Task 4: ローカル `.env` に `CF_DNS_API_TOKEN` を追加（運用者作業）

**Files:**
- Modify: `/Users/seiyu/workspaces/projects/dev-container/.env`（`.gitignore` 済み・コミットしない）

**Interfaces:**
- Consumes: 運用者が Cloudflare で発行した API トークン（DNS:Edit + Zone:Read、Zone は challtech.dev 限定）。

- [ ] **Step 1: トークンの有効性を単体確認**

（トークン発行後）Run: `curl -s -H "Authorization: Bearer <発行したトークン>" "https://api.cloudflare.com/client/v4/user/tokens/verify" | jq -r '.result.status'`
Expected: `active`

- [ ] **Step 2: `.env` に行を追加**

`.env` の末尾（GCP 行は残したまま）に以下を追加する。`<...>` は実トークンに置換:

```dotenv
# Cloudflare DNS設定
CF_DNS_API_TOKEN=<発行したトークン>
```

- [ ] **Step 3: 補間確認（秘匿値を出力しない）**

Run: `docker compose -f compose.cloudflare.yaml config | grep -c 'CF_DNS_API_TOKEN'`
Expected: `1`（値は表示せず存在のみ確認。エラー/警告が出ないこと）。

- [ ] **Step 4: コミットしないことを確認**

Run: `git status --porcelain .env; echo "exit=$?"`
Expected: `.env` が出力されない（`.gitignore` 済みのため追跡対象外）。**このタスクはコミットしない。**

---

### Task 5: 切替（運用者作業・任意タイミング）

**Files:** なし（Docker 操作のみ）

**Interfaces:**
- Consumes: Task 2 の `compose.cloudflare.yaml`、Task 4 の `.env`。

> 設計方針により証明書は既存 `ssl` ボリュームの acme.json を流用し強制再取得はしない。詳細な切替/ロールバック/CAA/Cloud DNS 後片付け手順は設計ドキュメント `docs/superpowers/specs/2026-07-18-traefik-cloudflare-dns-migration-design.md` の「運用ランブック」を参照。

- [ ] **Step 1: gcloud 版を停止**

Run: `docker compose -f compose.gcloud.yaml down`
Expected: proxy 等が停止する。

- [ ] **Step 2: Cloudflare 版で起動**

Run: `docker compose -f compose.cloudflare.yaml up -d`
Expected: コンテナが起動する。

- [ ] **Step 3: proxy ログ確認**

Run: `docker compose -f compose.cloudflare.yaml logs --tail=50 proxy`
Expected: エラーなく起動。証明書エラーが出ないこと（既存証明書流用のため通常は再取得ログは出ない）。

- [ ] **Step 4: ロールバック手順（問題発生時のみ）**

Run: `docker compose -f compose.cloudflare.yaml down && docker compose -f compose.gcloud.yaml up -d`
Expected: gcloud 版に復帰。`ssl` ボリューム（acme.json）は共有のため既存証明書をそのまま使う。

---

## Self-Review

**1. Spec coverage:**
- compose.cloudflare.yaml 作成 → Task 2 ✓
- .env.cloudflare.example 作成 → Task 1 ✓
- .env 更新（CF_DNS_API_TOKEN） → Task 4 ✓
- README 更新 → Task 3 ✓
- 運用ランブック（トークン検証/切替/ロールバック/CAA/Cloud DNS 後片付け） → 設計ドキュメント参照 + Task 4/5 で実行部分をカバー ✓
- ZeroSSL 維持・provider のみ変更・resolvers 追加・secrets 削除 → Task 2 の内容に反映 ✓

**2. Placeholder scan:** `<発行したトークン>` は運用者が置換する実値プレースホルダ（秘匿値のため plan に実値は書けない）。それ以外に TODO/TBD なし。

**3. Type consistency:** ファイル名（`compose.cloudflare.yaml` / `.env.cloudflare.example`）、環境変数名（`CF_DNS_API_TOKEN`）、resolver 名（`zerossl`）は全タスクで一貫。
