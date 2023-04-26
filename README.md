# ローカル共通コンテナ

## 環境構築

.env.exampleをコピーして.envを作成する
.envの項目を全部埋める

### ネットワーク作成

```sh
  docker network create web --subnet "192.168.100.0/24"
  docker network create dev-container
```
  

### 起動

`docker compose up -d`

### URL

#### proxy dashboard

https://proxy.local.challtech.dev

#### mail

https://mail.local.challtech.dev

#### minio

https://minio.local.challtech.dev

