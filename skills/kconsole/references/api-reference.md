# KConsole API Reference

Base URL: `https://api-kconsole.koompi.cloud`

## General Operations

### List Services
**GET /api/orgs/{orgId}/services**

### Get Service Details
**GET /api/services/{serviceId}**

### Update Service Configuration
**PUT /api/services/{serviceId}**
Updatable Fields:
- `envVars`: Array of `{key, value}`. **Replaces entire array, include all vars.**
- `resources`: `{cpu, memory, replicas}`
- `healthCheck`
- `name`
- `domain`: Sets public URL (e.g., `{"domain": "my-app"}`)

### Delete Service
**DELETE /api/services/{serviceId}**
*CRITICAL: ONLY use when explicitly asked to "delete" or "destroy".*

---

## Creation Endpoints

### Create Git Service
**POST /api/orgs/{orgId}/services/git**
```json
{
  "name": "my-app",
  "source": {
    "repository": "https://github.com/user/my-app",
    "branch": "main",
    "buildType": "dockerfile"
  },
  "resourceSizeId": "small"
}
```

### Create Zip Upload Service
1. **POST /api/orgs/{orgId}/storage/upload-token**
   Get pre-signed URL. Required: `filename`, `contentType` (`application/zip`), `size`, `visibility` (`private`).
2. **PUT to pre-signed URL**
   Upload the zip binary.
3. **POST /api/orgs/{orgId}/services/upload**
```json
{
  "name": "my-zip-app",
  "r2Key": "org_xxx/private/filename.zip",
  "fileName": "my-app.zip",
  "fileSize": 5242880,
  "buildType": "auto",
  "resourceSizeId": "small"
}
```

### Create Docker Image Service
**POST /api/orgs/{orgId}/services/image**
Deploy from a pre-built Docker image.
```json
{
  "name": "nginx-app",
  "image": "nginx:latest",
  "resourceSizeId": "small"
}
```

### Upload New Version (Zip Services)
**POST /api/services/{serviceId}/reupload**
Uploads new code without deleting the service.
```json
{
  "r2Key": "org_xxx/private/new-filename.zip",
  "fileName": "my-app-v2.zip",
  "fileSize": 5300000
}
```

### Rollback to Previous Version
**POST /api/services/{serviceId}/rollback**
```json
{ "version": 2 }
```
Zip services keep 10 versions by default.

### Create Database Service
**POST /api/orgs/{orgId}/services/database**
```json
{
  "name": "my-postgres",
  "engine": "postgres",
  "version": "15",
  "databaseName": "appdb",
  "username": "admin",
  "password": "SecurePassword123!",
  "enableTunnel": true,
  "resourceSizeId": "small",
  "storage": 20
}
```
*Engines: `postgres`, `mongodb`, `mysql`, `mariadb`, `redis`*

### Create VPS Service
**POST /api/orgs/{orgId}/services/vps**
```json
{
  "name": "my-vps",
  "os": "ubuntu",
  "version": "22.04",
  "authType": "password",
  "password": "SecurePassword123!",
  "enableTunnel": true,
  "resourceSizeId": "medium",
  "storage": 50
}
```

### Create Broker Service
**POST /api/orgs/{orgId}/services/broker**
```json
{
  "name": "my-queue",
  "engine": "rabbitmq",
  "version": "3.12",
  "enableTunnel": true,
  "resourceSizeId": "small",
  "storage": 20
}
```
*Engines: `rabbitmq`, `redis`, `kafka`*

---

## Advanced Management

### Scale Service
**POST /api/services/{serviceId}/scale**
Body: `{"replicas": 3}`

### Redeploy Service
**POST /api/services/{serviceId}/redeploy**

### Get Build Logs
**GET /api/builds/{serviceId}**
Returns recent build logs with status (`running`, `success`, `failed`). Log fields: `message`, `stream` (stdout/stderr), `timestamp`.

### Get Runtime Logs
**GET /api/logs/{serviceId}**
Query params: `limit` (default 1000), `instanceId` (filter to specific instance), `since` (ISO date, logs after timestamp).

### Check Domain Configuration
**GET /api/services/{serviceId}/domain**
Returns subdomain, customDomains, allowedIps, blockedIps.

### Verify Custom Domain
**POST /api/services/{serviceId}/domain/verify**
```json
{ "domain": "app.example.com" }
```

### VPS Tunnels
**POST /api/services/{serviceId}/vps-tunnels**
Body: `{"port": 22, "name": "SSH", "subdomain": "my-vps-ssh"}`

### Add Custom Domain
**POST /api/services/{serviceId}/domain/custom**
Body: `{"domain": "app.example.com", "email": "admin@example.com"}`
DNS: `CNAME app.example.com -> tunnel.koompi.cloud`

### Delete VPS Tunnel
**DELETE /api/services/{serviceId}/vps-tunnels/{subdomain}**

---

## Resource Sizes
`resourceSizeId` options:
- `nano`: 0.25 CPU, 256MB, 10GB storage
- `micro`: 0.5 CPU, 512MB, 20GB storage
- `small`: 1 CPU, 1024MB, 50GB storage
- `medium`: 2 CPU, 2048MB, 100GB storage
- `large`: 4 CPU, 4096MB, 200GB storage
- `xlarge`: 8 CPU, 8192MB, 500GB storage
