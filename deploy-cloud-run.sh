#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${FIREBASE_PROJECT_ID:-wattly-smart-energy-2026}"
REGION="${CLOUD_RUN_REGION:-asia-south1}"
SERVICE="${CLOUD_RUN_SERVICE:-wattly-api}"

: "${DEVICE_API_KEY:?Load DEVICE_API_KEY before deploying}"
: "${TARIFF_ADMIN_KEY:?Load TARIFF_ADMIN_KEY before deploying}"

gcloud config set project "$PROJECT_ID"
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com firestore.googleapis.com

gcloud run deploy "$SERVICE" \
  --source . \
  --region "$REGION" \
  --allow-unauthenticated \
  --memory 2Gi \
  --cpu 2 \
  --timeout 300 \
  --min-instances 0 \
  --max-instances 2 \
  --set-env-vars "FIREBASE_PROJECT_ID=$PROJECT_ID,PERSISTENCE_BACKEND=firestore,PERSISTENCE_STRICT=true,REQUIRE_USER_AUTH=true,PERSISTENCE_SAMPLE_SECONDS=60,DEVICE_API_KEY=$DEVICE_API_KEY,TARIFF_ADMIN_KEY=$TARIFF_ADMIN_KEY"

gcloud run services describe "$SERVICE" \
  --region "$REGION" \
  --format='value(status.url)'
