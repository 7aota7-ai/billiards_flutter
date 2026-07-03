#!/usr/bin/env bash
# Cloud Run デプロイ（v0.1.5+）。git pull 済みか確認してからデプロイする。
set -euo pipefail

SERVICE="${SERVICE:-billiards-ball-detector}"
REGION="${REGION:-asia-northeast1}"
CORS_ORIGIN="${CORS_ORIGIN:-https://7aota7-ai.github.io}"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

echo "==> git pull"
git pull origin main

VERSION="$(grep '^APP_VERSION' tools/ball_detector/server.py | sed 's/.*= *"\(.*\)".*/\1/')"
GIT_SHA="$(git rev-parse --short HEAD)"
echo "==> local version: ${VERSION}  git: ${GIT_SHA}"

if [[ "$VERSION" < "0.1.5" ]]; then
  echo "ERROR: server.py が古い (${VERSION})。git pull 後も 0.1.5 未満なら main を確認してください。" >&2
  exit 1
fi

PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
echo "==> gcloud project: ${PROJECT:-<unset>}"

cd tools/ball_detector

echo "==> gcloud run deploy ${SERVICE} (${REGION})"
gcloud run deploy "$SERVICE" \
  --source . \
  --region "$REGION" \
  --platform managed \
  --allow-unauthenticated \
  --memory 512Mi \
  --cpu 1 \
  --timeout 60s \
  --max-instances 2 \
  --set-env-vars "CORS_ORIGINS=${CORS_ORIGIN},MAX_UPLOAD_BYTES=10485760,RATE_LIMIT_REQUESTS=30,RATE_LIMIT_WINDOW_SEC=60,LOG_DETECT_RESULTS=false,GIT_SHA=${GIT_SHA}"

URL="$(gcloud run services describe "$SERVICE" --region "$REGION" --format='value(status.url)')"
REVISION="$(gcloud run services describe "$SERVICE" --region "$REGION" --format='value(status.latestReadyRevisionName)')"
echo "==> URL: ${URL}"
echo "==> revision: ${REVISION}"

echo "==> /health"
curl -sS "${URL}/health" | tee /tmp/ball-detector-health.json
echo

python3 - <<'PY'
import json, sys
h = json.load(open("/tmp/ball-detector-health.json"))
v = h.get("version", "")
if v < "0.1.5":
    print(f"ERROR: deployed version is still {v!r}", file=sys.stderr)
    sys.exit(1)
print(f"OK: version={v} git_sha={h.get('git_sha')}")
PY
