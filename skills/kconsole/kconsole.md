---
name: kconsole
description: Deploy, update, and manage applications, databases, and VPS instances on KOOMPI Cloud KConsole. Use when interacting with kconsole.koompi.cloud or deploying code/zips/images. Includes self-learning protocols to update its own API reference when KOOMPI Cloud updates endpoints.
---

# KConsole API Agent Skill (Self-Learning Edition)

This skill enables the agent to interact with the KConsole API to manage infrastructure on KOOMPI Cloud.

## Core Directives

1. **NEVER DELETE UNLESS EXPLICITLY COMMANDED**
   - User says "Update the app", "Add env var", "Deploy new version" → **DO NOT DELETE**.
   - Use `PUT` to modify existing services. Use `POST /reupload` for new zip deployments.
   - Only use `DELETE` when the user explicitly says "delete", "destroy", or "remove".

2. **Self-Learning Protocol (Crucial)**
   - When encountering a `400 Bad Request`, `404 Not Found`, or unknown schema error from KConsole:
     1. Analyze the response body or documentation to find the new required format.
     2. Immediately use the `edit` tool to update the corresponding endpoint in `/data/workspace/koompi-docs/references/api-reference.md`.
     3. If a new service type or parameter is discovered, add it to the documentation.
     4. Log the learning event in `MEMORY.md`.

## Authentication & Verification

All API requests require:
```bash
Authorization: Bearer {API_TOKEN}
```
**API Base URL:** `https://api-kconsole.koompi.cloud`

**Verify Credentials & Get Org ID:**
```bash
curl -H "Authorization: Bearer {YOUR_TOKEN}" \
  https://api-kconsole.koompi.cloud/api/auth/me
```
*Extract `organization._id` from the response.*

## References

KConsole API is extensive. Load these references only when performing specific tasks:

- **API Reference**: See [references/api-reference.md](references/api-reference.md) for endpoints (List, Create Git/Zip/DB/VPS/Broker, Update Config, Set Domain).
- **Deployment Guides**: See [references/deployment-guides.md](references/deployment-guides.md) for pre-deployment analysis, Dockerfile generation, and multi-service detection logic.

## Quick Operations Guide

- **Update Env Vars/Resources:** `PUT /api/services/{serviceId}`
- **Deploy New Zip Version:** `POST /api/services/{serviceId}/reupload` (DO NOT delete first!)
- **Set Public Domain:** `PUT /api/services/{serviceId}` with `{"domain": "my-app"}`
- **Create Service:** Refer to `references/api-reference.md` for specific service types.
