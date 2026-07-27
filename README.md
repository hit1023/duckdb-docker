# DuckDB Docker環境

DuckDB Web UIをDockerで動かす環境です。ブラウザからSQLの実行・可視化ができます。

## 構成

- **DuckDB Web UI**: ブラウザからSQLを実行・可視化（`duckdb --ui` をコンテナ内で起動）
- **nginx**: IPv6/IPv4プロキシ（DuckDB UIのlocalhost問題を解決。コンテナ内で `[::1]:4213` にリッスンしているDuckDB UIを80番にプロキシする）

コンテナは Ubuntu 24.04 ベースで、起動時にDuckDB CLI（最新版）と `ui` 拡張をインストールする（[Dockerfile](Dockerfile)参照）。

## セットアップ方法

### 前提条件

- Docker / Docker Compose が使えること
- （任意）ホスト側でSQLファイルを流し込む場合はローカルにファイルがあればOK。DuckDB CLI自体をホストにインストールする必要はない

### 初回セットアップ

```bash
cd /Volumes/USBSSD/docker/DuckDB

# イメージをビルドして起動（初回はDuckDB CLIのダウンロード等で数分かかる）
docker compose up -d --build
# または: ./run.sh up
```

起動後、ブラウザで http://localhost:4213 を開くとDuckDB Web UIが表示される。

停止する場合：

```bash
docker compose down
# または: ./run.sh down
```

### ポート

| ポート | 用途 |
|--------|------|
| 4213   | DuckDB Web UI（nginx経由、ホストからはこちらを使う） |
| 4214   | DuckDB Web UIへの直接アクセス（コンテナ内nginxを経由しない。切り分け用） |

### ディレクトリ構成

```
.
├── docker-compose.yml   # Docker設定（ポート、ボリュームマウント）
├── Dockerfile           # DuckDB CLI + nginx をインストールするイメージ定義
├── entrypoint.sh        # コンテナ起動時にnginxとDuckDB UIを立ち上げるスクリプト
├── nginx.conf           # nginxプロキシ設定
├── run.sh               # 操作用ラッパースクリプト（後述）
├── sample.sql           # 動作確認用のサンプルSQL
├── data/                # DBファイル・エクスポートデータ（.gitignore済み、コンテナ内 /db にマウント）
│   └── notebooks/       # Web UIのノートブック・設定（ui.db、.gitignore済み）
└── queries/             # 自分で書いたSQLファイルの置き場
```

`data/` はコンテナの `/db` にマウントされているため、Web UI・CLIどちらからも同じファイルとして見える。

## 利用方法

### 1. Web UIから使う

1. `docker compose up -d`（または `./run.sh up`）で起動
2. ブラウザで http://localhost:4213 を開く
3. ノートブック内でDBファイルにアタッチしてSQLを実行

```sql
-- data/ 以下のDBファイルにアタッチ（コンテナ内パスは /db 配下）
ATTACH '/db/mydb.duckdb' AS mydb;
USE mydb;

-- CSV/Parquetを直接クエリすることも可能
SELECT * FROM read_csv_auto('/db/users.csv');
SELECT * FROM read_parquet('/db/users.parquet');
```

### 2. コンテナ内のDuckDB CLIを直接使う

```bash
# コンテナ内でシェルを取得してCLIを起動
docker compose exec duckdb duckdb /db/mydb.duckdb

# ワンライナーでクエリを実行
docker compose exec duckdb duckdb /db/mydb.duckdb -c "SELECT * FROM users;"

# SQLファイルをホストから流し込む（-Tで標準入力をリダイレクト）
docker compose exec -T duckdb duckdb /db/mydb.duckdb < sample.sql
docker compose exec -T duckdb duckdb /db/mydb.duckdb < queries/foo.sql
```

> Web UI（`duckdb --ui`）とCLI（`duckdb`）は同じDBファイルを同時に書き込みモードで開けない。Web UI起動中にCLIから書き込みたい場合は `-readonly` を付けるか、一旦Web UI側のアタッチを解除する。

### 3. run.sh を使う（推奨）

上記のdocker composeコマンドをまとめたラッパースクリプト。リポジトリ直下から実行する。

```bash
./run.sh up               # ビルドしてバックグラウンド起動
./run.sh down              # コンテナ停止・削除
./run.sh restart           # 再起動
./run.sh logs              # ログをフォロー表示
./run.sh shell             # コンテナ内でDuckDB CLIを起動（./data/mydb.duckdbにアタッチ）
./run.sh sql sample.sql    # SQLファイルを ./data/mydb.duckdb に対して実行
./run.sh sql queries/foo.sql mydb2.duckdb  # DBファイルを指定して実行
```

初回は `chmod +x run.sh` が必要（リポジトリには実行権限付きでコミット済み）。

### 4. クライアントアプリから使う

Harlequin（TUI）でも接続可能：

```bash
brew install harlequin

# 読み取り専用（Web UI起動中でも接続可）
harlequin -r ./data/mydb.duckdb

# 読み書き（Web UI・CLIが同DBを開いていないこと）
harlequin ./data/mydb.duckdb
```

## 動作確認

```bash
./run.sh up
./run.sh sql sample.sql testcheck.duckdb
```

`sample.sql` は users テーブルを作成し、都市ごとの人数・平均年齢を集計するサンプル。以下のような結果がターミナルに出力されれば環境構築は成功。

```
┌─────────┬───────┬──────────┐
│  city   │ 人数  │ 平均年齢 │
│ varchar │ int64 │  double  │
├─────────┼───────┼──────────┤
│ 横浜    │     2 │     29.0 │
│ 東京    │     1 │     25.0 │
│ 大阪    │     1 │     35.0 │
└─────────┴───────┴──────────┘
```

> `data/mydb.duckdb` は既にサンプルとは異なる列構成の `users` テーブルを持っている場合がある（列数不一致で `Binder Error` になる）。動作確認だけなら上記のように別名のDBファイル（例: `testcheck.duckdb`）を指定するのが安全。確認用に作られたファイルは `rm data/testcheck.duckdb` で削除してよい。
