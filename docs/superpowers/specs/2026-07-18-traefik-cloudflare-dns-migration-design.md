# Traefik DNS-01 チャレンジ Cloudflare 移行 設計

## 背景

ドメイン `challtech.dev` の権威 DNS を Google Cloud DNS から Cloudflare へ移行済み
（NS: `anton.ns.cloudflare.com` / `demi.ns.cloudflare.com`、切替確認済み）。
Traefik の ACME DNS-01 チャレンジはまだ Google Cloud DNS 向け設定のため、
DNS プロバイダを Cloudflare に差し替える。

## 確定した決定事項

| 項目 | 決定 | 理由 |
|------|------|------|
| CA | ZeroSSL 維持 | 既存 resolver `zerossl` / caserver / EAB 認証を流用。変更は DNS プロバイダのみでリスク最小 |
| ファイル構成 | Cloudflare 版を新規追加、gcloud/aws は残す | 既存のプロバイダ別パターン（`compose.<provider>.yaml`）踏襲。ロールバック可能 |
| 証明書 | 既存 `ssl` ボリュームの acme.json を流用、強制再取得なし | ドメイン不変のため既存証明書は失効まで有効。自然更新時に新プロバイダが使われる |

## リポジトリ変更（成果物）

### 1. `compose.cloudflare.yaml`（新規）

`compose.gcloud.yaml` をベースに以下だけ差し替える。

- ファイル冒頭の `secrets:` ブロックを削除（GCP サービスアカウント JSON 不要）
- `proxy` サービスの `secrets:` 参照を削除
- `proxy` の `environment:` を `CF_DNS_API_TOKEN: "${CF_DNS_API_TOKEN}"` のみに変更（`GCE_SERVICE_ACCOUNT_FILE` / `GCE_PROJECT` を削除）
- command の `--certificatesresolvers.zerossl.acme.dnschallenge.provider=gcloud` → `cloudflare`
- command に `--certificatesresolvers.zerossl.acme.dnschallenge.resolvers=1.1.1.1:53,8.8.8.8:53` を追加
  （TXT レコード伝播チェックを外部リゾルバで行い、ローカルリゾルバによる誤判定を防ぐ）
- caserver / email / storage / eab.kid / eab.hmacEncoded は **変更なし**
- 各サービス（proxy / mail / minio）の Traefik ラベルは **変更なし**（`tls.certresolver=zerossl` 等そのまま）
- mysql8 / redis6 / mail / minio / dns / networks / volumes は gcloud 版と同一

### 2. `.env.cloudflare.example`（新規）

`.env.gcloud.example` をベースに、GCP 設定ブロックを削除し Cloudflare 設定を追加。

```
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

### 3. `.env`（更新）

`CF_DNS_API_TOKEN=<実トークン>` の行を追加する（実トークンは運用者が記入）。
GCP 関連行はロールバック用に残す。`.env` は `.gitignore` 済みのためコミットされない。

### 4. `README.md`（更新）

「Cloudflare を使用する場合」セクションを環境構築・起動の両方に追加。

```sh
docker compose -f compose.cloudflare.yaml up -d
```

## 運用ランブック（リポジトリ外の手作業）

これらは DNS 側の運用手順であり、リポジトリのファイル変更ではない。

### A. Cloudflare API トークン発行
Cloudflare ダッシュボード → My Profile → API Tokens → Create Token → Custom token
- 権限: `Zone → DNS → Edit`, `Zone → Zone → Read`
- Zone Resources: `challtech.dev` のみに限定（Global API Key は使わない）
- 発行値を `.env` の `CF_DNS_API_TOKEN` に設定

### B. DNS レコード確認
- `*.local.challtech.dev A → 127.0.0.1`、**DNS only（グレー雲）** 必須
  （プロキシ ON だとループバック/プライベート IP は登録エラー。他端末からもアクセスするなら
  `127.0.0.1` ではなく Traefik ホストの LAN IP に）
- DNS-01 チャレンジ自体は Traefik が `_acme-challenge.local.challtech.dev` の TXT を
  Cloudflare API 経由で作成・削除するため、上記 A レコードは名前解決用

### C. CAA レコードの注意
ZeroSSL の証明書発行元は **Sectigo**。CAA を張る場合は次のいずれか。
- `challtech.dev. CAA 0 issue "sectigo.com"`
- CAA を張らない（誰でも発行可＝デフォルト）

**重要**: 旧 Google Cloud DNS 由来の `0 issue "pki.goog"` が残っていると ZeroSSL/Sectigo が
弾かれるため、削除するか `sectigo.com` に置き換える。

### D. トークン単体の疎通確認（acme.json に触れず検証）
自然更新を待つ方針のため、更新が走る前にトークンの有効性を単体で確認しておく。

```sh
curl -s -H "Authorization: Bearer $CF_DNS_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/user/tokens/verify" | jq .
# → "status": "active" を確認
```

### E. 切替とロールバック

切替:
```sh
docker compose -f compose.gcloud.yaml down
docker compose -f compose.cloudflare.yaml up -d
docker compose -f compose.cloudflare.yaml logs -f proxy
```

ロールバック（Cloudflare 側で問題が出た場合）:
```sh
docker compose -f compose.cloudflare.yaml down
docker compose -f compose.gcloud.yaml up -d
```

`ssl` ボリューム（acme.json）は共有のため、切替・ロールバックとも既存証明書をそのまま使う。

### F. Cloud DNS の後片付け（移行安定後）
1. バックアップをエクスポート
   ```sh
   gcloud dns record-sets export challtech-dev-backup.txt --zone=YOUR_ZONE --zone-file-format
   ```
2. MX / TXT（SPF・DKIM・DMARC）が存在する場合、Cloudflare 側へ移行済みか確認
   （例: `dig MX challtech.dev`, `dig TXT challtech.dev` を Cloudflare NS 相手に）
3. 証明書更新が Cloudflare 経由で通り、数日安定してからゾーンを削除
   （レコードを先に削除する必要あり）

## 検証方針の補足（トレードオフ）

強制再取得しないため、Traefik 起動直後には Cloudflare DNS-01 の成否は分からない。
リスク低減として運用ランブック D（トークン単体疎通確認）を必ず実施する。
更新が走る残 30 日時点で `Certificates obtained for domain` がログに出れば移行成功。
失敗時は E のロールバックで gcloud に即戻せる。

## スコープ外

- Let's Encrypt への CA 変更（今回は ZeroSSL 維持）
- gcloud / aws プロバイダ設定の削除（ロールバック用に残す）
- 証明書の強制再取得
