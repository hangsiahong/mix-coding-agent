# KConsole Deployment Guides

This document outlines the logic the agent must follow when deploying applications, especially from Zip files.

## 1. Pre-Deployment Analysis
When given a zip file, always inspect it first:
```bash
unzip -l my-app.zip
```
Look for:
- `Dockerfile`
- `package.json` (Node.js)
- `requirements.txt` (Python)
- `pom.xml` (Java)
- `docker-compose.yml`

## 2. Multi-Service Detection
If multiple `package.json` or `Dockerfile` files exist in different directories, stop and ask the user which services to deploy.
- Deploy each as a separate KConsole service.
- If a `docker-compose.yml` exists, use `buildType: "compose"`.

## 3. BuildType Selection
- Has Dockerfile: `dockerfile`
- Node.js (no Dockerfile): `auto` (Nixpacks)
- Python (no Dockerfile): `auto`
- Static site: `nixpacks`
- Multi-container: `compose`

## 4. Dockerfile Generation
If no Dockerfile is found and `auto` buildType fails or is undesired, generate one.

**Node.js (Express):**
```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
```

**Next.js:**
```dockerfile
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:18-alpine AS runner
WORKDIR /app
ENV NODE_ENV production
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/node_modules ./node_modules
EXPOSE 3000
CMD ["node", "server.js"]
```

**Python (Flask):**
```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 5000
CMD ["python", "app.py"]
```

**Static Site (React/Vue/Angular):**
```dockerfile
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```
