FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    unzip \
    nginx \
    && rm -rf /var/lib/apt/lists/*

# DuckDB CLI をインストール
RUN curl -fsSL https://install.duckdb.org | sh

# インストール先を PATH に追加
ENV PATH="/root/.duckdb/cli/latest:$PATH"

# DuckDB UI拡張をインストール
RUN duckdb -c "INSTALL ui;"

# nginx設定をコピー
COPY nginx.conf /etc/nginx/nginx.conf

# 起動スクリプト
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /db

EXPOSE 80

CMD ["/entrypoint.sh"]
