FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# DuckDB CLI をインストール
RUN curl -fsSL https://install.duckdb.org | sh

# インストール先を PATH に追加
ENV PATH="/root/.duckdb/cli/latest:$PATH"

WORKDIR /data

CMD ["bash"]
