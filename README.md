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

##### Parquetとは（補足）

Parquetは CSV/JSON のような**行指向のテキスト形式ではなく**、Apache製の**列指向（columnar）バイナリ形式**。カラムごとにまとめて圧縮して保持するため、`cat`や`xxd`でそのまま人間が読める内容にはならない。特徴は以下の通り：

- **列指向**: 行ではなく列単位でデータをまとめて格納するので、特定の列だけを読む集計クエリが高速・省メモリ
- **バイナリ+圧縮**: SNAPPY/GZIP等で列ごとに圧縮されるため、同じデータでもCSV/JSONよりファイルサイズが小さくなりやすい
- **スキーマ内蔵**: 列名・型がファイル自体に埋め込まれている（CSVのようにヘッダー行だけで型が曖昧、ということがない）
- **フッターにメタデータ**: ファイル末尾にスキーマや統計情報を持つフッターがあり、拡張子や中身の先頭・末尾に `PAR1` というマジックナンバーが付く

実際に3つのファイルを比べると、同じ内容でもサイズが異なる：

```bash
$ ls -la data/users.csv data/users.json data/users.parquet
-rw-r--r--  57 data/users.csv
-rw-r--r-- 113 data/users.json
-rw-r--r-- 718 data/users.parquet   # ヘッダー/フッターのメタデータ分、小さいデータではむしろ大きくなる
```

バイナリであることは `xxd` で確認できる（先頭と末尾に `PAR1` というマジックナンバーが見える）：

```bash
$ xxd data/users.parquet | head -1
00000000: 5041 5231 1504 1510 1514 4c15 0415 0000  PAR1......L.....

$ xxd data/users.parquet | tail -1
000002c0: 6432 6636 2900 6a01 0000 5041 5231        d2f6).j...PAR1
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

DuckDBには内部のスキーマ・列ごとの圧縮方式を覗ける関数もある（テキストで中身を見られない代わりに、これで構造を確認できる）：

```sql
-- スキーマ構造（ネスト情報含む）
SELECT name, type, num_children FROM parquet_schema('/db/users.parquet');
```

```
┌───────────────┬────────────┬──────────────┐
│     name      │    type    │ num_children │
│    varchar    │  varchar   │    int64     │
├───────────────┼────────────┼──────────────┤
│ duckdb_schema │ NULL       │            3 │
│ id            │ INT32      │         NULL │
│ name          │ BYTE_ARRAY │         NULL │
│ city          │ BYTE_ARRAY │         NULL │
└───────────────┴────────────┴──────────────┘
```

```sql
-- 列ごとの圧縮方式・サイズ
SELECT column_id, path_in_schema, num_values, compression,
       total_compressed_size, total_uncompressed_size
FROM parquet_metadata('/db/users.parquet');
```

```
┌───────────┬────────────────┬────────────┬─────────────┬───────────────────────┬─────────────────────────┐
│ column_id │ path_in_schema │ num_values │ compression │ total_compressed_size │ total_uncompressed_size │
│   int64   │    varchar     │   int64    │   varchar   │         int64         │          int64          │
├───────────┼────────────────┼────────────┼─────────────┼───────────────────────┼─────────────────────────┤
│         0 │ id             │          2 │ SNAPPY      │                    56 │                     111 │
│         1 │ name           │          2 │ SNAPPY      │                    79 │                     135 │
│         2 │ city           │          2 │ SNAPPY      │                    68 │                     123 │
└───────────┴────────────────┴────────────┴─────────────┴───────────────────────┴─────────────────────────┘
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

### 5. JOINの例

users（顧客）と orders（注文）の2テーブルで確認：

```sql
CREATE OR REPLACE TABLE users (id INTEGER, name VARCHAR, city VARCHAR);
INSERT INTO users VALUES (1,'田中太郎','横浜'),(2,'鈴木花子','東京'),(3,'佐藤次郎','大阪');

CREATE OR REPLACE TABLE orders (order_id INTEGER, user_id INTEGER, item VARCHAR, price INTEGER);
INSERT INTO orders VALUES (101,1,'ノートPC',120000),(102,1,'マウス',3000),(103,2,'キーボード',8000);
```

**INNER JOIN**（注文があるユーザーだけ）:

```sql
SELECT u.name, u.city, o.item, o.price
FROM users u
JOIN orders o ON u.id = o.user_id
ORDER BY u.id, o.order_id;
```

```
┌──────────┬─────────┬────────────┬────────┐
│   name   │  city   │    item    │ price  │
│ varchar  │ varchar │  varchar   │ int32  │
├──────────┼─────────┼────────────┼────────┤
│ 田中太郎 │ 横浜    │ ノートPC   │ 120000 │
│ 田中太郎 │ 横浜    │ マウス     │   3000 │
│ 鈴木花子 │ 東京    │ キーボード │   8000 │
└──────────┴─────────┴────────────┴────────┘
```

**LEFT JOIN**（注文が無い佐藤次郎も出てくる）:

```sql
SELECT u.name, u.city, o.item, o.price
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
ORDER BY u.id;
```

```
┌──────────┬─────────┬────────────┬────────┐
│   name   │  city   │    item    │ price  │
│ varchar  │ varchar │  varchar   │ int32  │
├──────────┼─────────┼────────────┼────────┤
│ 田中太郎 │ 横浜    │ マウス     │   3000 │
│ 田中太郎 │ 横浜    │ ノートPC   │ 120000 │
│ 鈴木花子 │ 東京    │ キーボード │   8000 │
│ 佐藤次郎 │ 大阪    │ NULL       │ NULL   │
└──────────┴─────────┴────────────┴────────┘
```

**LEFT JOIN + GROUP BY**（ユーザーごとの注文数・合計金額、未購入は0件・NULL）:

```sql
SELECT u.name, count(o.order_id) AS 注文数, sum(o.price) AS 合計金額
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.name
ORDER BY u.name;
```

```
┌──────────┬────────┬──────────┐
│   name   │ 注文数 │ 合計金額 │
│ varchar  │ int64  │  int128  │
├──────────┼────────┼──────────┤
│ 佐藤次郎 │      0 │     NULL │
│ 田中太郎 │      2 │   123000 │
│ 鈴木花子 │      1 │     8000 │
└──────────┴────────┴──────────┘
```

## MySQLとの比較

DuckDBは標準SQL寄りで、MySQLと共通する構文も多いが差異もある。普段MySQLに慣れている場合の対応表：

| やりたいこと | MySQL | DuckDB |
|---|---|---|
| CLIで接続 | `mysql -u user -p db` | `duckdb mydb.duckdb`（本環境では `docker compose exec duckdb duckdb /db/mydb.duckdb`） |
| テーブル一覧 | `SHOW TABLES;` | `SHOW TABLES;`（同じ構文が使える） |
| テーブル構造確認 | `DESCRIBE users;` / `SHOW COLUMNS FROM users;` | `DESCRIBE users;`（同じ構文が使える） |
| DB一覧 | `SHOW DATABASES;` | `SHOW DATABASES;`（ATTACHしたDB一覧が出る） |
| 文字列連結 | `CONCAT(a, b)` | `a \|\| b`（標準SQLの `\|\|` を使う。`CONCAT()` 関数もある） |
| 識別子のクォート | `` `name` ``（バッククォート） | `"name"`（ダブルクォート。バッククォートは使えない＝検証済み） |
| LIMIT / OFFSET | `LIMIT 10 OFFSET 5` | `LIMIT 10 OFFSET 5`（同じ構文） |
| 自動採番 | `id INT AUTO_INCREMENT` | `CREATE SEQUENCE`＋`DEFAULT nextval('...')`（`GENERATED ALWAYS AS IDENTITY`は未実装＝検証済み） |
| 現在時刻 | `NOW()` | `now()`（同じ関数名で使える） |
| CSVインポート | `LOAD DATA INFILE '...' INTO TABLE t;` | `CREATE TABLE t AS SELECT * FROM read_csv_auto('...');`（ファイルを直接クエリできるのでインポート自体が不要な場合も多い） |
| 外部DBに接続 | 標準で対応 | `mysql_scanner` 拡張が必要（`INSTALL mysql; LOAD mysql; ATTACH '...' AS mysqldb (TYPE mysql);`） |
| ストレージ形式 | 行指向（InnoDB等） | 列指向（DuckDB独自形式 + Parquetとの親和性が高い） |
| 用途の想定 | サーバー常駐のOLTP（トランザクション処理） | 単一プロセス埋め込みのOLAP（分析・集計処理） |

`SHOW TABLES` / `DESCRIBE` / `LIMIT OFFSET` / `NOW()` はMySQLとほぼ同じ書き方で動くため、単純な参照・集計クエリは移植しやすい。一方でバッククォートでの識別子クォートやMySQL固有関数（`GROUP_CONCAT`等）はそのままでは動かないため置き換えが必要。

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
