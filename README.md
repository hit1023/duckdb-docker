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

#### 対応フォーマット

このイメージには標準で `json` と `parquet` 拡張が入っており（`core_functions`同様に自動ロード）、追加インストールなしで以下がすぐ使える。

```sql
SELECT * FROM read_csv_auto('/db/users.csv');
SELECT * FROM read_parquet('/db/users.parquet');
SELECT * FROM read_json_auto('/db/users.json');

-- globパターンで複数ファイルをまとめて読み込みも可能
SELECT * FROM read_parquet('/db/*.parquet');
```

##### Parquetの例

`data/users.parquet`（`id, name, city` の2行）を実際にクエリすると：

```sql
SELECT * FROM read_parquet('/db/users.parquet');
```

```
┌───────┬──────────┬─────────┐
│  id   │   name   │  city   │
│ int32 │ varchar  │ varchar │
├───────┼──────────┼─────────┤
│     1 │ 田中太郎 │ 横浜    │
│     2 │ 鈴木花子 │ 東京    │
└───────┴──────────┴─────────┘
```

CSVから作る場合は `COPY` で変換できる：

```sql
COPY (SELECT * FROM read_csv_auto('/db/users.csv')) TO '/db/users.parquet' (FORMAT parquet);
```

##### JSONの例

`data/users.json`（配列形式のレコード）:

```json
[
  {"id": 1, "name": "田中太郎", "city": "横浜"},
  {"id": 2, "name": "鈴木花子", "city": "東京"}
]
```

これを実際にクエリすると：

```sql
SELECT * FROM read_json_auto('/db/users.json');
```

```
┌───────┬──────────┬─────────┐
│  id   │   name   │  city   │
│ int64 │ varchar  │ varchar │
├───────┼──────────┼─────────┤
│     1 │ 田中太郎 │ 横浜    │
│     2 │ 鈴木花子 │ 東京    │
└───────┴──────────┴─────────┘
```

それ以外の形式はDuckDBの拡張機能をコンテナ内から追加インストールすれば使える（コンテナはインターネットに出られるので `INSTALL` 自体は可能。イメージには焼き込まれていないため、コンテナを再作成すると再インストールが必要）。

| 拡張 | 用途 | 有効化コマンド |
|---|---|---|
| `httpfs` | S3 / HTTP(S) / GCSなど、リモートのCSV・Parquetを直接クエリ | `INSTALL httpfs; LOAD httpfs;` |
| `sqlite_scanner` | SQLiteファイルをそのままATTACH | `INSTALL sqlite; LOAD sqlite;` |
| `postgres_scanner` | PostgreSQLに直接ATTACHしてクエリ | `INSTALL postgres; LOAD postgres;` |
| `mysql_scanner` | MySQLに直接ATTACH | `INSTALL mysql; LOAD mysql;` |
| `spatial` | Shapefile/GeoJSON等の地理空間データ、`ST_Read`経由でExcel(.xlsx)読み込みも可 | `INSTALL spatial; LOAD spatial;` |
| `iceberg` | Apache Icebergテーブルの読み込み | `INSTALL iceberg; LOAD iceberg;` |
| `delta` | Delta Lakeテーブルの読み込み | `INSTALL delta; LOAD delta;` |
| `avro` | Avroファイルの読み込み | `INSTALL avro; LOAD avro;` |

常用する拡張がある場合は [Dockerfile](Dockerfile) の `RUN duckdb -c "INSTALL ui;"` の行に `INSTALL httpfs;` などを追記してイメージに焼き込んでおくと、コンテナ再作成のたびに入れ直す必要がなくなる。

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
