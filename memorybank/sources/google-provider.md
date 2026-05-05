# Source: Google Provider Implementation

## Overview
Implemented support for Google AI (Studio and Vertex) as a first-class provider. Supports both API Key (Studio) and gcloud-based auth (Vertex).

## Details
- **Provider Name**: `google`
- **Supported API Surfaces**:
  - **Google AI Studio**: Static API key. Fast, easy for personal use.
  - **Google Vertex AI**: Enterprise-grade. Uses `gcloud auth print-access-token`.
- **Key Configuration**:
  - `AGENT_PROVIDER="google"`
  - `AGENT_MODEL="google/gemini-1.5-pro"` (Note the `google/` prefix for Vertex compatibility)
  - `GOOGLE_REGION` (Vertex only, defaults to `us-central1`)
  - `GOOGLE_PROJECT_ID` (Vertex only)
- **Automatic Auth Suppression**: `mix` detects Google provider and suppresses the standard `Authorization: Bearer` header if `x-goog-api-key` is used, preventing `OVERLOADED_CREDENTIALS` errors.
- **Preview Models**: Models matching `gemini-3` automatically switch region to `global` on Vertex.

## Implementation Files
- `src/providers/google.sh`: Provider logic (activation, login, token management).
- `src/16_api.sh` & `src/18_streaming_api_call.sh`: Header suppression logic.
