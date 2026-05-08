# Google Vertex AI Integration Guide for kconsole

## Prerequisites
- GCP Project active.
- Billing enabled.
- Vertex AI API enabled.
- Service Account with "Vertex AI User" role.

## Step 1: GCP Setup
1. Go GCP Console.
2. Create or select existing Project. Note `PROJECT_ID`.
3. Go APIs & Services. Search "Vertex AI API". Click Enable.

## Step 2: Authentication Configuration
1. Go IAM & Admin -> Service Accounts.
2. Create Service Account. Name: `kconsole-vertex-sa`.
3. Grant Role: `Vertex AI User`.
4. Keys -> Add Key -> Create New Key -> JSON.
5. Download JSON key file.
6. Set environment variable for kconsole runtime: 
   `export GOOGLE_APPLICATION_CREDENTIALS="/path/to/kconsole-vertex-sa.json"`

## Step 3: API Endpoint Definition
Vertex AI requires specific region endpoints. kconsole routing logic must handle this.

**Base URL Pattern:**
`https://[REGION]-aiplatform.googleapis.com/v1/projects/[PROJECT_ID]/locations/[REGION]/publishers/google/models/[MODEL_ID]:streamGenerateContent`

**Common Regions:** `us-central1`, `europe-west4`, `asia-southeast1`.
**Common Models:** `gemini-3-flash-preview`, `gemini-3.1-flash-lite-preview`, `gemini-3.1-pro-preview`, and image models like `imagen-3.0-generate-001` (or latest preview).

## Step 4: Token Generation (Gateway side)
kconsole must dynamically generate OAuth tokens using the Service Account JSON.
- If Node/Python: use official Google Auth SDK to fetch token.
- HTTP Header required for request: `Authorization: Bearer <OAUTH_TOKEN>`

## Step 5: Payload Translation (Adapter layer)
kconsole must adapt standard OpenAI-style payloads to Vertex Gemini format.

**kconsole Input (OpenAI style):**
```json
{
  "model": "gemini-3.1-pro-preview",
  "messages": [{"role": "user", "content": "Hello"}]
}
```

**kconsole Output (Vertex style):**
```json
{
  "contents": [
    {
      "role": "user",
      "parts": [{"text": "Hello"}]
    }
  ],
  "generationConfig": {
    "temperature": 0.7
  }
}
```

## Step 6: Integration Test
1. Start kconsole with Vertex adapter enabled.
2. Send test cURL to kconsole gateway port:
```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <kconsole_api_key>" \
  -d '{
    "model": "vertex/gemini-3.1-pro-preview",
    "messages": [{"role": "user", "content": "Test vertex integration"}]
  }'
```
3. Verify successful response format matches OpenAI standard.