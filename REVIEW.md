# Known Issues Requiring Manual Review

Issues that cannot be resolved by editing installer files alone. They depend on upstream images, cluster configuration, or runtime inspection.

## Docker Compose

### Health check binary availability (HIGH)
Whether health checks work depends on what binaries exist inside `artifacts.plane.so/makeplane/plane-*` images. The `web`, `space`, `admin` health checks use `wget`, and the `live` health check uses `wget`. If these images are distroless or don't include `wget`, health checks will fail and the proxy will never start. **Action**: Pull images and verify: `docker run --rm --entrypoint sh <image> -c "which wget curl node python3"`. Adjust health checks based on findings.

### Backend management commands may not exist (MEDIUM)
All backend services call `python manage.py wait_for_db` and `python manage.py wait_for_migrations`. These are custom Django management commands that must exist in the Plane backend image. If they don't exist for the targeted `APP_RELEASE`, services will fail. **Action**: Verify against the Plane source for your target release.

### Image registry availability (MEDIUM)
Application images are pulled from `artifacts.plane.so/makeplane/`. If this registry goes down, deployments fail. **Action**: Consider mirroring images to Docker Hub (`makeplane/*`) or a local registry.

### CERT_EMAIL format (LOW)
The `CERT_EMAIL` value includes a `email ` prefix (e.g. `CERT_EMAIL=email admin@example.com`). This is Caddy's `tls` directive syntax. If the `plane-proxy` image's Caddyfile uses `{$CERT_EMAIL}` as a raw directive argument, this is correct. If it expects just the email address, TLS will break. **Action**: Inspect the `plane-proxy` image's Caddyfile to confirm.

### Proxy routing is opaque (LOW)
The `plane-proxy` Caddy image has routing rules baked in. If upstream changes route paths or expects different environment variables, there is no way to debug without rebuilding the image. **Action**: For custom routing, mount a custom Caddyfile as a volume override.

### MinIO image age (LOW)
MinIO is pinned to `RELEASE.2024-06-13T22-53-53Z` for reproducibility. This version may have known CVEs. **Action**: Periodically check for security advisories and update the pin.

## Helm Chart

### API readiness probe path (MEDIUM)
The API readiness/liveness probes hit `GET /` on port 8000. If Plane's Django API returns non-2xx for unauthenticated root requests, pods will never become ready. The `startupProbe` with `failureThreshold: 30` provides a long grace period. **Action**: After deploying, verify the API root returns 200. If it returns 401/404, change the probe path to a known health endpoint.

### Worker/beat-worker liveness probes (MEDIUM)
The Celery worker liveness probe uses `celery inspect ping` which requires the worker to be responsive. In high-load scenarios this may time out and cause unnecessary restarts. The beat-worker probe uses `pgrep`. **Action**: Monitor probe behavior under load and adjust timeouts if needed.

### StorageClass data durability (LOW)
StatefulSets use the cluster's default StorageClass when `storageClass: ""`. Whether data survives pod rescheduling depends on the provisioner's reclaim policy. **Action**: Verify your default StorageClass has `reclaimPolicy: Retain` for production data.

### `appVersion` is "stable" (LOW)
`Chart.yaml` uses `appVersion: "stable"` rather than a semantic version. This makes it hard to audit which Plane version is deployed. **Action**: Pin to a specific version (e.g. `0.23.0`) if tracking is important.

### Special characters in passwords (LOW)
URL helpers use `urlquery` to encode passwords in connection strings, which handles most special characters. However, some edge-case characters may still cause issues with specific database drivers. **Action**: Use hex-only passwords (the default when generated with `openssl rand -hex`) to avoid any encoding issues.

## Not Implemented (by design)

These were identified during audit but are deferred as they add complexity without clear immediate benefit for the primary use case:

- **NetworkPolicy**: Would restrict inter-pod traffic. Useful in multi-tenant clusters but adds complexity.
- **PodDisruptionBudget**: Only relevant when running >1 replica and performing node drains.
- **Pod topology spread / affinity**: Only relevant for multi-node HA deployments.
- **ServiceAccount creation**: All pods use the default SA. A dedicated SA with minimal RBAC is a hardening step.
- **securityContext**: Setting `runAsNonRoot`, `readOnlyRootFilesystem`, etc. requires verifying each upstream image supports it. Some images (especially postgres, minio) require root or writable filesystems.
- **Redis authentication**: Adding `--requirepass` would require coordinating the password across Redis config and all connection URLs. The Redis instance is only accessible within the Docker/K8s network.
