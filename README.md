# Plane Self-Hosted Installers

Self-hosting installers for [Plane](https://plane.so), the open-source project management tool.

Two deployment methods are provided:

| Method | Best for |
|--------|----------|
| [Docker Compose](#docker-compose) | Single-server deployments, development, small teams |
| [Helm (Kubernetes)](#helm-kubernetes) | Production clusters, high availability, auto-scaling |

## Architecture

Plane consists of the following services:

| Service | Image | Port | Description |
|---------|-------|------|-------------|
| **web** | `plane-frontend` | 3000 | Main web UI |
| **space** | `plane-space` | 3000 | Public project pages |
| **admin** | `plane-admin` | 3000 | Admin (god-mode) panel |
| **api** | `plane-backend` | 8000 | Django REST API |
| **worker** | `plane-backend` | - | Celery async worker |
| **beat-worker** | `plane-backend` | - | Celery beat scheduler |
| **live** | `plane-live` | 3000 | Real-time WebSocket server |
| **proxy** | `plane-proxy` | 80/443 | Caddy reverse proxy (Docker Compose only) |

Infrastructure dependencies:

| Component | Image | Purpose |
|-----------|-------|---------|
| PostgreSQL 15 | `postgres:15.7-alpine` | Primary database |
| Valkey 7.2 | `valkey/valkey:7.2.11-alpine` | Cache (Redis-compatible) |
| RabbitMQ 3.13 | `rabbitmq:3.13.6-management-alpine` | Celery message broker |
| MinIO | `minio/minio:latest` | S3-compatible file storage |

## Prerequisites

- **Docker Compose**: Docker Engine 24+ with Compose V2
- **Helm**: Kubernetes 1.27+, Helm 3.12+, an Ingress controller (e.g. nginx-ingress)
- **Hardware**: 2 CPU cores, 4 GB RAM minimum (8 GB recommended for production)

---

## Docker Compose

### Quick start

```bash
cd docker

# Generate .env with random secrets
./setup.sh

# Start all services
docker compose up -d

# Open http://localhost in your browser
```

### Production deployment with TLS

```bash
cd docker

# Generate .env configured for your domain with Let's Encrypt TLS
./setup.sh --domain plane.example.com --email admin@example.com

docker compose up -d
```

### Configuration

All configuration lives in `docker/.env`. The setup script generates one with random secrets. Key settings:

| Variable | Description |
|----------|-------------|
| `APP_DOMAIN` | Your domain name (default: `localhost`) |
| `APP_RELEASE` | Image tag: `stable`, `v1.2.3`, `preview` |
| `SECRET_KEY` | Django secret key (auto-generated) |
| `POSTGRES_PASSWORD` | Database password (auto-generated) |
| `LISTEN_HTTP_PORT` | Host HTTP port (default: `80`) |
| `LISTEN_HTTPS_PORT` | Host HTTPS port (default: `443`) |
| `GUNICORN_WORKERS` | API worker count (default: `1`) |
| `FILE_SIZE_LIMIT` | Max upload size in bytes (default: `5242880`) |

See `docker/.env.example` for all available options.

### Using external services

To use an external PostgreSQL, Redis, RabbitMQ, or S3:

1. Comment out the corresponding service in `docker-compose.yml`
2. Update the connection URL in `.env` (e.g. `DATABASE_URL`, `REDIS_URL`, `AMQP_URL`)
3. For external S3, set `USE_MINIO=0` and configure `AWS_*` variables

### Useful commands

```bash
# View logs
docker compose logs -f api

# Restart a single service
docker compose restart api

# Stop everything
docker compose down

# Stop and destroy all data
docker compose down -v

# Update to latest images
docker compose pull && docker compose up -d

# Backup PostgreSQL
docker compose exec plane-db pg_dump -U plane plane > backup.sql
```

---

## Helm (Kubernetes)

### Quick start

```bash
cd helm

helm install plane ./plane-ce \
  --namespace plane \
  --create-namespace \
  --set ingress.appHost=plane.example.com \
  --set secrets.secretKey=$(openssl rand -hex 32) \
  --set secrets.liveServerSecretKey=$(openssl rand -hex 32) \
  --set postgres.password=$(openssl rand -hex 32) \
  --set rabbitmq.password=$(openssl rand -hex 32) \
  --set minio.accessKey=$(openssl rand -hex 16) \
  --set minio.secretKey=$(openssl rand -hex 32)
```

### Production deployment with custom values

Create a `values-production.yaml`:

```yaml
ingress:
  appHost: plane.example.com
  tls:
    enabled: true
    secretName: plane-tls

secrets:
  existingSecret: plane-secrets  # pre-created K8s Secret

api:
  replicas: 3
  gunicornWorkers: 4
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: "2"
      memory: 2Gi

worker:
  replicas: 2

web:
  replicas: 2

postgres:
  local: false
  externalUrl: "postgresql://plane:password@rds-host:5432/plane"

redis:
  local: false
  externalUrl: "redis://elasticache-host:6379/"

rabbitmq:
  local: false
  externalUrl: "amqp://user:pass@amazon-mq-host:5672/plane"

minio:
  local: false
  external:
    endpoint: "https://s3.amazonaws.com"
    accessKey: "AKIA..."
    secretKey: "..."
    region: "us-east-1"
    bucketName: "plane-uploads"
```

```bash
helm install plane ./plane-ce \
  --namespace plane \
  --create-namespace \
  -f values-production.yaml
```

### Configuration

All settings are in `helm/plane-ce/values.yaml`. Key sections:

| Section | Description |
|---------|-------------|
| `image.*` | Registry, tag, pull policy |
| `ingress.*` | Host, TLS, ingress class, annotations |
| `secrets.*` | App secrets or reference to existing K8s Secret |
| `api.*` | Replicas, Gunicorn workers, resources |
| `worker.*` / `beatWorker.*` | Celery configuration |
| `web.*` / `space.*` / `admin.*` / `live.*` | Frontend replicas and resources |
| `postgres.*` | Local StatefulSet or external URL |
| `redis.*` | Local StatefulSet or external URL |
| `rabbitmq.*` | Local StatefulSet or external URL |
| `minio.*` | Local StatefulSet or external S3 |

### Using an existing Kubernetes Secret

Create a Secret with these keys:

```bash
kubectl create secret generic plane-secrets \
  --namespace plane \
  --from-literal=SECRET_KEY=$(openssl rand -hex 32) \
  --from-literal=LIVE_SERVER_SECRET_KEY=$(openssl rand -hex 32) \
  --from-literal=DATABASE_URL="postgresql://plane:pass@host/plane" \
  --from-literal=REDIS_URL="redis://host:6379/" \
  --from-literal=AMQP_URL="amqp://user:pass@host:5672/plane" \
  --from-literal=AWS_ACCESS_KEY_ID="access-key" \
  --from-literal=AWS_SECRET_ACCESS_KEY="secret-key" \
  --from-literal=POSTGRES_PASSWORD="pass" \
  --from-literal=RABBITMQ_PASSWORD="pass"
```

Then reference it:

```yaml
secrets:
  existingSecret: plane-secrets
```

### Useful commands

```bash
# Check status
helm status plane -n plane

# View pods
kubectl get pods -n plane

# Upgrade
helm upgrade plane ./plane-ce -n plane -f values-production.yaml

# Uninstall
helm uninstall plane -n plane

# View API logs
kubectl logs -f deployment/plane-api -n plane

# Run migrations manually
kubectl exec -it deployment/plane-api -n plane -- python manage.py migrate
```

---

## Post-installation

1. Open your Plane instance in a browser
2. Create your admin account on first visit
3. Access the admin panel at `/god-mode` to configure:
   - Email (SMTP) settings
   - OAuth/SSO providers
   - Instance-level settings

## Upgrading

### Docker Compose

```bash
cd docker

# Update the APP_RELEASE in .env (or leave as "stable")
docker compose pull
docker compose up -d
```

### Helm

```bash
helm upgrade plane ./plane-ce \
  --namespace plane \
  --set image.tag=v1.2.3
```

The migrator job runs automatically on every `helm upgrade`.

## Backup and restore

### Docker Compose

```bash
# Backup
docker compose exec plane-db pg_dump -U plane plane > plane-backup.sql
docker compose cp plane-minio:/export ./minio-backup

# Restore
docker compose exec -T plane-db psql -U plane plane < plane-backup.sql
docker compose cp ./minio-backup/. plane-minio:/export
```

### Kubernetes

```bash
# Backup
kubectl exec -n plane statefulset/plane-postgres -- pg_dump -U plane plane > plane-backup.sql

# Restore
kubectl exec -i -n plane statefulset/plane-postgres -- psql -U plane plane < plane-backup.sql
```
