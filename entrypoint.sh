#!/bin/bash
set -e

# nginxをバックグラウンドで起動
nginx

# DuckDB UI を起動（フォアグラウンド）
exec duckdb --ui
