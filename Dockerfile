# syntax=docker/dockerfile:1

###############################################
#   ChatGPT All-in-One image for ArgoCD
#   Components: Vault, Redis, Kafka, Postgres,
#   Prometheus, Grafana, Loki, Tempo, Kyverno
#   Author: exea-centrum
###############################################

FROM ubuntu:24.04 AS base

LABEL org.opencontainers.image.authors="exea-centrum"
LABEL org.opencontainers.image.source="https://github.com/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgadm-chat"
LABEL org.opencontainers.image.description="All-in-one ArgoCD stack generator with Vault, Redis, Kafka, Postgres, Grafana, Loki, Tempo, Kyverno."

# Instalacja narzędzi
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    bash curl wget git jq gettext-base unzip \
    ca-certificates gnupg lsb-release nano vim \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Skrypt i manifesty
COPY chatgpt.sh /app/chatgpt.sh
COPY manifests /app/manifests

# Uprawnienia
RUN chmod +x /app/chatgpt.sh

# Zmienne środowiskowe
ENV APP_NAME="website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgadm-chat"
ENV NAMESPACE="davtroallinone"
ENV VAULT_ADDR="http://vault:8200"
ENV VAULT_TOKEN="root"

# Healthcheck Vaulta
HEALTHCHECK --interval=60s --timeout=10s --start-period=20s \
  CMD curl -fs $VAULT_ADDR/v1/sys/health || echo "Vault not reachable yet"

# Domyślne polecenie
ENTRYPOINT ["/app/chatgpt.sh"]
CMD ["generate"]
