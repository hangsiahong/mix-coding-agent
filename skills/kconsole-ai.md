---
name: kconsole-ai
description: Generate images and videos via KConsole AI Gateway (Gemini, Imagen, Veo). Supports text-to-image, image-to-image (with reference), and text-to-video. Use when you are asked to generate an image, create a video, edit an image, or use AI models like Gemini image gen, Veo video gen, or Imagen. Also for chat completions when you explicitly wants KConsole AI instead of the built-in model.
---

# KConsole AI Gateway Skill

> Complete guide for interacting with KConsole's AI Gateway, fully compatible with OpenAI SDKs.

Unified OpenAI-compatible API proxy hosted on KOOMPI Cloud. Supports text, image, and video generation from Google Gemini/Veo and GLM. Handles billing, rate limiting, and translates all requests behind a standard OpenAI-compatible API interface.

## 🔗 Base URL & Authentication

- **Base URL:** `https://ai.koompi.cloud/v1`
- **API Key:** Available as `$KCONSOLE_AI_KEY` env var, or read from `/data/workspace/.env` → `KCONSOLE_AI_KEY`
- **Auth:** `Authorization: Bearer <key>`

For SDK usage:
```typescript
import OpenAI from "openai";
const openai = new OpenAI({
  baseURL: "https://ai.koompi.cloud/v1",
  apiKey: "your-kconsole-api-key"
});
```

## 🤖 Available Models

List dynamically:
```bash
curl -X GET "https://ai.koompi.cloud/v1/models" -H "Authorization: Bearer $KEY"
```

### Popular Supported Models

**Text & Chat:**
- `gemini-3.1-pro-preview`, `gemini-3-flash-preview`, `gemini-2.5-pro`
- `glm-5-turbo`, `glm-5`, `glm-4.7-flash`, `glm-4-plus`, `glm-4-air`

**Image Generation:**
- `gemini-3.1-flash-image-preview` — Fast, good quality (default, Nano Banana 2)
- `gemini-3-pro-image-preview` — Higher quality
- `imagen-3.0-generate-001` — Google Imagen 3

**Video Generation:**
- `veo-3.1-lite-generate-preview` — Fast, no reference image support
- `veo-3.1-generate-preview` — Full model, supports reference images via `uri` format only

---

## 💬 Chat Completions (Text)

Standard `/v1/chat/completions` endpoint. Streaming fully supported (`"stream": true`).

```bash
KEY="$KCONSOLE_AI_KEY"
curl -s -X POST "https://ai.koompi.cloud/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "glm-5-turbo",
    "messages": [{"role":"user","content":"PROMPT HERE"}],
    "stream": true
  }'
```

---

## 🎨 Image Generation

Gateway intercepts Google's Gemini/Imagen endpoints and routes them through standard OpenAI image generation payloads at `/v1/images/generations`.

### Parameters

| Param | Type | Required | Description |
|---|---|---|---|
| `model` | string | ✅ | Image model name |
| `prompt` | string | ✅ | Text description |
| `n` | number | ❌ | Number of images (default 1) |
| `size` | string | ❌ | Aspect ratio (see below) |
| `response_format` | string | ❌ | Use `b64_json` |
| `image` | string | ❌ | Base64 input image for image-to-image transformation or image-to-video (first frame) |
| `reference_image` | string | ❌ | Base64 reference image for style/content guidance (Veo 3.1+ only, not Lite) |
| `image_url` | string | ❌ | URL to reference/input image (gateway downloads and converts it) |

### Aspect Ratios (size param)
- 1:1 → `1024x1024`
- 16:9 → `1792x1024`
- 9:16 → `1024x1792`
- 4:3 → `1152x896`
- 3:4 → `896x1152`

### Image-to-Image Examples

**Via `image_url`:**
```bash
KEY="$KCONSOLE_AI_KEY"
curl -s -X POST "https://ai.koompi.cloud/v1/images/generations" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemini-3.1-flash-image-preview",
    "prompt": "Transform this into a watercolor painting style",
    "n": 1,
    "size": "1024x1024",
    "response_format": "b64_json",
    "image_url": "https://example.com/photo.jpg"
  }' | python3 -c "
import sys,json,base64
d = json.load(sys.stdin)['data'][0]['b64_json']
with open('edited_image.png','wb') as f: f.write(base64.b64decode(d))
print('Saved: edited_image.png')
"
```

**Via `reference_image` (base64 local file):**
```bash
KEY="$KCONSOLE_AI_KEY"
# For large base64 payloads, write to temp file to avoid arg length limits
python3 -c "
import json, base64, subprocess, os
env = dict(l.strip().split('=', 1) for l in open('/data/workspace/.env') if '=' in l)
key = env.get('KCONSOLE_AI_KEY','').strip().strip('\"')
with open('/path/to/local/image.jpg','rb') as f: img_b64 = base64.b64encode(f.read()).decode()
with open('/tmp/req_body.json','w') as f: json.dump({
  'model': 'gemini-3.1-flash-image-preview',
  'prompt': 'Add a sunset sky background',
  'n': 1, 'size': '1024x1024', 'response_format': 'b64_json',
  'reference_image': img_b64
}, f)
r = subprocess.run(['curl','-s','-X','POST','https://ai.koompi.cloud/v1/images/generations',
  '-H',f'Authorization: Bearer {key}','-H','Content-Type: application/json',
  '-d','@/tmp/req_body.json'], capture_output=True, text=True, timeout=120)
data = json.loads(r.stdout)
img = base64.b64decode(data['data'][0]['b64_json'])
with open('edited_image.png','wb') as f: f.write(img)
print('Saved, size:', len(img))
"
```

### SDK Examples (TypeScript)

**Text-to-Image:**
```typescript
const response = await openai.images.generate({
  model: "gemini-3.1-flash-image-preview",
  prompt: "A futuristic cyberpunk city skyline under heavy rain, neon lights",
  n: 1,
  size: "1024x1024",
  response_format: "b64_json"
});
const imageBase64 = response.data[0].b64_json;
```

**Image-to-Image (via base64 `image` param):**
```typescript
import fs from 'fs';
const inputImageBuffer = fs.readFileSync('./input_image.jpg');
const inputImageBase64 = inputImageBuffer.toString('base64');

const response = await openai.images.generate({
  model: "gemini-3.1-flash-image-preview",
  prompt: "Transform this into a watercolor painting style",
  image: inputImageBase64, // Primary input image
  n: 1,
  size: "1024x1024",
  response_format: "b64_json"
});
fs.writeFileSync('output_image.jpg', Buffer.from(response.data[0].b64_json, 'base64'));
```

**Image-to-Image (via URL):**
```typescript
const response = await openai.images.generate({
  model: "gemini-3.1-flash-image-preview",
  prompt: "Make this image look like a Van Gogh painting",
  image_url: "https://example.com/my-photo.jpg",
  n: 1,
  size: "1024x1024",
  response_format: "b64_json"
});
```

---

## 🎬 Video Generation

### Text-to-Video
```bash
KEY="$KCONSOLE_AI_KEY"
curl -s -X POST "https://ai.koompi.cloud/v1/images/generations" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "veo-3.1-lite-generate-preview",
    "prompt": "DESCRIPTION HERE",
    "n": 1
  }' > video_response.json && \
python3 -c "
import json,base64
d = json.load(open('video_response.json'))['data'][0]['b64_json']
with open('generated_video.mp4','wb') as f: f.write(base64.b64decode(d))
print('Saved: generated_video.mp4')
"
```

⚠️ Video generation takes **2-5 minutes** (up to 10 min with reference image). Use long timeout (600s+). The gateway polls Google automatically and returns the MP4 as b64_json.

### Image-to-Video (Animate from First Frame)

Use the `image` parameter to provide a starting frame for the video:

```bash
# Write payload to temp file for large base64
python3 -c "
import json, base64, subprocess, os
key = os.environ.get('KCONSOLE_AI_KEY', '')
with open('/path/to/first_frame.jpg','rb') as f: img_b64 = base64.b64encode(f.read()).decode()
with open('/tmp/veo_req.json','w') as f: json.dump({
  'model': 'veo-3.1-generate-preview',
  'prompt': 'The person starts walking forward into the sunset',
  'image': img_b64,
  'n': 1
}, f)
r = subprocess.run(['curl','-s','-X','POST','https://ai.koompi.cloud/v1/images/generations',
  '-H',f'Authorization: Bearer {key}','-H','Content-Type: application/json',
  '-d','@/tmp/veo_req.json'], capture_output=True, text=True, timeout=600)
data = json.loads(r.stdout)
if 'error' in data: print('ERROR:', data)
else:
  vid = base64.b64decode(data['data'][0]['b64_json'])
  with open('output.mp4','wb') as f: f.write(vid)
  print('Saved, size:', len(vid))
"
```

**SDK Example (TypeScript):**
```typescript
import fs from 'fs';
const startingFrameBuffer = fs.readFileSync('./first_frame.jpg');
const startingFrameBase64 = startingFrameBuffer.toString('base64');

const response = await openai.images.generate({
  model: "veo-3.1-generate-preview", // Full Veo 3.1, not Lite
  prompt: "The person starts walking forward into the sunset",
  image: startingFrameBase64, // Starting frame of the video
  n: 1
}, {
  timeout: 10 * 60 * 1000 // 10 Minutes for video generation
});
fs.writeFileSync('generated_video.mp4', Buffer.from(response.data[0].b64_json, 'base64'));
```

### Reference Image for Video (Style/Content Guidance)

> ⚠️ Reference images for style/content guidance are only supported on **Veo 3.1 and Veo 3.1 Fast**, NOT on Veo 3.1 Lite.

Use `reference_image` to preserve a person's face or object's appearance:

**SDK Example (TypeScript):**
```typescript
import fs from 'fs';
const faceImageBuffer = fs.readFileSync('./person_face.jpg');
const faceImageBase64 = faceImageBuffer.toString('base64');

const response = await openai.images.generate({
  model: "veo-3.1-generate-preview", // Must use full Veo 3.1, not Lite!
  prompt: "A professional footballer in red jersey number 10, striking a powerful shot on goal",
  reference_image: faceImageBase64, // Preserves the person's appearance
  n: 1
}, {
  timeout: 10 * 60 * 1000 // 10 Minutes
});
fs.writeFileSync('generated_video.mp4', Buffer.from(response.data[0].b64_json, 'base64'));
```

**cURL Example:**
```bash
python3 -c "
import json, base64, subprocess, os
key = os.environ.get('KCONSOLE_AI_KEY', '')
with open('./person_face.jpg','rb') as f: img_b64 = base64.b64encode(f.read()).decode()
with open('/tmp/veo_req.json','w') as f: json.dump({
  'model': 'veo-3.1-generate-preview',
  'prompt': 'Transform this person into a footballer scoring a goal',
  'reference_image': img_b64,
  'n': 1
}, f)
r = subprocess.run(['curl','-s','-X','POST','https://ai.koompi.cloud/v1/images/generations',
  '-H',f'Authorization: Bearer {key}','-H','Content-Type: application/json',
  '-d','@/tmp/veo_req.json'], capture_output=True, text=True, timeout=600)
data = json.loads(r.stdout)
if 'error' in data: print('ERROR:', data)
else:
n  vid = base64.b64decode(data['data'][0]['b64_json'])
  with open('generated_video.mp4','wb') as f: f.write(vid)
  print('Saved, size:', len(vid))
"
```

**Combining `image` + `reference_image`:**
You can use both together to animate a specific frame while preserving a person's appearance:
```typescript
const response = await openai.images.generate({
  model: "veo-3.1-generate-preview",
  prompt: "The person starts running and kicks the ball",
  image: startingFrameBase64,       // Starting frame to animate
  reference_image: faceImageBase64, // Preserves face appearance
  n: 1
}, { timeout: 10 * 60 * 1000 });
```

---

## ⚠️ Known Limitations

- **Veo Lite (`veo-3.1-lite`):** No reference image support. Text prompt only.
- **Veo Full (`veo-3.1`):** Supports reference images. Use `image` for first-frame animation, `reference_image` for style/content guidance. You can combine both.
- **Gemini Pro Image (`gemini-3-pro-image-preview`):** Rejects reference images smaller than 1024px. Use `gemini-3.1-flash-image-preview` for smaller refs.
- **Celebrity Names:** Gemini safety filter blocks named real people in prompts (e.g., "Messi"). Workaround: describe visually instead (e.g., "a legendary Argentine goalkeeper in blue and white").
- **Command line arg length:** Large base64 payloads exceed shell limits. Always write payload to a temp JSON file (`/tmp/req_body.json`) and use `@/tmp/req_body.json` with curl.

## ⚠️ Language Rule

When generating images/videos with Cambodian/Khmer themes, NEVER use Thai script, Thai text, or Thai signage. Khmer (ភាសាខ្មែរ) and Thai (ภาษาไทย) are different languages with different scripts. Always specify in the prompt: "Use Khmer/Cambodian script only, NO Thai text, NO Thai language."

## 📋 Workflow

1. Parse request → determine type (image/video/chat, reference image involved?)
2. Pick model:
   - Images: `gemini-3.1-flash-image-preview` (default), `gemini-3-pro-image-preview` (higher quality, needs 1024px+ ref)
   - Video: `veo-3.1-lite-generate-preview` (text only), `veo-3.1-generate-preview` (ref support, gateway limitation)
3. If reference image: encode to base64, write to `/tmp/req_body.json`, use `curl -d @/tmp/req_body.json`
4. Execute with long timeout for video (600s+)
5. Decode b64_json → save to workspace
6. Send result to user
7. For video: warn about wait time before starting
