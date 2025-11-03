# syntax=docker/dockerfile:1

FROM ubuntu:24.04

LABEL maintainer="exea-centrum"
LABEL app="website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgadm-chat"

# Instalacja narzędzi i bibliotek systemowych
RUN apt-get update && apt-get install -y \
    bash curl jq wget git gettext-base unzip \
    && rm -rf /var/lib/apt/lists/*

# Skopiuj skrypt i manifesty do obrazu
WORKDIR /app
COPY deep.sh /app/deep.sh
COPY manifests /app/manifests

# Uprawnienia i domyślny punkt startowy
RUN chmod +x /app/deep.sh

ENTRYPOINT ["/app/deep.sh"]
CMD ["generate"]
