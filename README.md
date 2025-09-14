# ローカル共通コンテナ

## 環境構築

### AWS Route53 を使用する場合

1. `.env.aws.example`をコピーして`.env`を作成する
2. `.env`の項目を全部埋める（AWS 関連の環境変数を設定）

### Google Cloud DNS を使用する場合

1. `.env.gcloud.example`をコピーして`.env`を作成する
2. `.env`の項目を全部埋める（GCP 関連の環境変数を設定）

### ネットワーク作成

```sh
  docker network create web --subnet "192.168.100.0/24"
  docker network create dev-container
```

### 起動

#### AWS Route53 を使用する場合

```sh
docker compose -f compose.aws.yml up -d
```

#### Google Cloud DNS を使用する場合

```sh
docker compose -f compose.gcloud.yml up -d
```

### URL

#### proxy dashboard

https://proxy.local.challtech.dev

#### mail

https://mail.local.challtech.dev

#### minio

https://minio.local.challtech.dev
