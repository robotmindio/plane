#!/usr/bin/env bash
# =============================================================================
# Plane Self-Hosted — Setup Script
# =============================================================================
# Generates .env with random secrets and validates prerequisites.
# Usage: ./setup.sh [--domain example.com] [--email admin@example.com]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
ENV_EXAMPLE="${SCRIPT_DIR}/.env.example"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { printf '\033[0;34m[INFO]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[0;33m[WARN]\033[0m  %s\n' "$*"; }
error() { printf '\033[0;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()   { error "$@"; exit 1; }

generate_secret() {
  openssl rand -hex 32
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
DOMAIN="localhost"
EMAIL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)
      [[ $# -ge 2 ]] || die "--domain requires a value"
      DOMAIN="$2"; shift 2 ;;
    --email)
      [[ $# -ge 2 ]] || die "--email requires a value"
      EMAIL="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--domain <domain>] [--email <email>]"
      echo ""
      echo "Options:"
      echo "  --domain   Domain name for Plane (default: localhost)"
      echo "  --email    Email for Let's Encrypt TLS certificates"
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
done

# Validate domain
if [[ -z "${DOMAIN}" ]]; then
  die "--domain value must not be empty"
fi
if [[ "${DOMAIN}" == http* ]]; then
  die "--domain should be a bare domain (e.g. plane.example.com), not a URL"
fi

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
info "Checking prerequisites..."

command -v docker   >/dev/null 2>&1 || die "Docker is not installed. See https://docs.docker.com/get-docker/"
command -v openssl  >/dev/null 2>&1 || die "openssl is not installed."

COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  die "Docker Compose is not installed. See https://docs.docker.com/compose/install/"
fi

info "Docker:  $(docker --version)"
info "Compose: $(${COMPOSE_CMD} version)"

# ---------------------------------------------------------------------------
# Generate .env
# ---------------------------------------------------------------------------
if [[ -f "${ENV_FILE}" ]]; then
  warn ".env already exists — skipping generation."
  warn "Delete .env and re-run this script to regenerate secrets."
else
  [[ -f "${ENV_EXAMPLE}" ]] || die ".env.example not found in ${SCRIPT_DIR}"

  info "Generating .env with random secrets..."

  SECRET_KEY="$(generate_secret)"
  POSTGRES_PASSWORD="$(generate_secret)"
  RABBITMQ_PASSWORD="$(generate_secret)"
  MINIO_ACCESS_KEY="$(generate_secret)"
  MINIO_SECRET_KEY="$(generate_secret)"
  LIVE_SECRET="$(generate_secret)"

  if [[ "${DOMAIN}" == "localhost" ]]; then
    WEB_URL="http://localhost"
    SITE_ADDRESS=":80"
    CERT_BLOCK="# CERT_EMAIL=
# CERT_ACME_CA="
  else
    WEB_URL="https://${DOMAIN}"
    SITE_ADDRESS="${DOMAIN}"
    if [[ -n "${EMAIL}" ]]; then
      CERT_BLOCK="CERT_EMAIL=email ${EMAIL}
CERT_ACME_CA=https://acme-v02.api.letsencrypt.org/directory"
    else
      CERT_BLOCK="# CERT_EMAIL=email admin@${DOMAIN}
# CERT_ACME_CA=https://acme-v02.api.letsencrypt.org/directory"
    fi
  fi

  cat > "${ENV_FILE}" <<EOF
# =============================================================================
# Plane Self-Hosted — Generated Configuration
# Generated on: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
# =============================================================================

# General
APP_DOMAIN=${DOMAIN}
APP_RELEASE=stable
WEB_URL=${WEB_URL}
DEBUG=0
CORS_ALLOWED_ORIGINS=${WEB_URL}
SECRET_KEY=${SECRET_KEY}
GUNICORN_WORKERS=1
API_KEY_RATE_LIMIT=60/minute
FILE_SIZE_LIMIT=5242880

# PostgreSQL
POSTGRES_USER=plane
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=plane
POSTGRES_PORT=5432
PGHOST=plane-db
PGDATABASE=plane

# Redis
REDIS_HOST=plane-redis
REDIS_PORT=6379

# RabbitMQ
RABBITMQ_HOST=plane-mq
RABBITMQ_PORT=5672
RABBITMQ_USER=plane
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD}
RABBITMQ_VHOST=plane

# MinIO / S3
USE_MINIO=1
AWS_ACCESS_KEY_ID=${MINIO_ACCESS_KEY}
AWS_SECRET_ACCESS_KEY=${MINIO_SECRET_KEY}
AWS_REGION=us-east-1
AWS_S3_ENDPOINT_URL=http://plane-minio:9000
AWS_S3_BUCKET_NAME=uploads

# Live server
LIVE_SERVER_SECRET_KEY=${LIVE_SECRET}
API_BASE_URL=http://api:8000

# Proxy
LISTEN_HTTP_PORT=80
LISTEN_HTTPS_PORT=443
SITE_ADDRESS=${SITE_ADDRESS}
TRUSTED_PROXIES=private_ranges
${CERT_BLOCK}

# Replicas
WEB_REPLICAS=1
SPACE_REPLICAS=1
ADMIN_REPLICAS=1
API_REPLICAS=1
WORKER_REPLICAS=1
LIVE_REPLICAS=1
EOF

  info ".env created with unique secrets."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
info "Setup complete. Next steps:"
echo ""
echo "  1. Review and adjust .env if needed"
echo "  2. Start Plane:"
echo ""
echo "     cd ${SCRIPT_DIR}"
echo "     ${COMPOSE_CMD} up -d"
echo ""
if [[ "${DOMAIN}" == "localhost" ]]; then
  DISPLAY_URL="http://localhost"
else
  DISPLAY_URL="https://${DOMAIN}"
fi
echo "  3. Open ${DISPLAY_URL} and create your admin account"
echo ""
if [[ "${DOMAIN}" != "localhost" && -z "${EMAIL}" ]]; then
  warn "No --email provided. TLS is disabled."
  warn "Re-run with --email to enable Let's Encrypt certificates."
fi
