# DuckDB Docker環境

DuckDB Web UIをDockerで動かす環境です。ブラウザからSQLの実行・可視化ができます。

## 構成

- **DuckDB Web UI**: ブラウザからSQLを実行・可視化
- **nginx**: IPv6/IPv4プロキシ（DuckDB UIのlocalhost問題を解決）

## 起動方法

```bash
docker compose up -d
```

ブラウザで http://localhost:4213 を開く。

## ディレクトリ構成

```
.
├── docker-compose.yml   # Docker設定
├── nginx.conf           # nginxプロキシ設定
├── data/                # DBファイル・エクスポートデータ（.gitignore済み）
└── queries/             # SQLファイル置き場
```

## DBファイルのアタッチ

Web UI内のノートブックで実行：

```sql
ATTACH '/db/mydb.duckdb' AS mydb;
```

## クライアントアプリ

Harlequin（TUI）でも接続可能：

```bash
brew install harlequin

# 読み取り専用（Web UI起動中）
harlequin -r ./data/mydb.duckdb

# 読み書き（Web UI停止中）
harlequin ./data/mydb.duckdb
```

## ポート

| ポート | 用途 |
|--------|------|
| 4213   | DuckDB Web UI（nginx経由） |
