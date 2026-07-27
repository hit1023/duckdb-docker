#!/bin/bash
# DuckDB Docker環境の操作をまとめたラッパースクリプト
set -e

cd "$(dirname "$0")"

usage() {
  cat <<EOF
使い方: ./run.sh <command> [args]

コマンド:
  up              コンテナをビルドしてバックグラウンド起動
  down            コンテナを停止・削除
  restart         コンテナを再起動
  logs            ログをフォロー表示
  shell           コンテナ内でDuckDB CLIを起動（./data/mydb.duckdbにアタッチ）
  sql <file> [db] SQLファイルを実行（db省略時は ./data/mydb.duckdb）
                  例: ./run.sh sql sample.sql
                      ./run.sh sql queries/foo.sql mydb2.duckdb
EOF
}

case "$1" in
  up)
    docker compose up -d --build
    echo "起動しました: http://localhost:4213"
    ;;
  down)
    docker compose down
    ;;
  restart)
    docker compose restart
    ;;
  logs)
    docker compose logs -f
    ;;
  shell)
    docker compose exec duckdb duckdb /db/mydb.duckdb
    ;;
  sql)
    FILE="$2"
    DB="${3:-mydb.duckdb}"
    if [ -z "$FILE" ]; then
      echo "エラー: SQLファイルを指定してください（例: ./run.sh sql sample.sql）" >&2
      exit 1
    fi
    docker compose exec -T duckdb duckdb "/db/$DB" < "$FILE"
    ;;
  *)
    usage
    exit 1
    ;;
esac
