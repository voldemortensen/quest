#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-quest}"
REGION="${AWS_REGION:-us-west-2}"
TAG="${TAG:-latest}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

docker buildx build --platform linux/amd64 --provenance=false \
  -f "$ROOT/Dockerfile" -t "$REGISTRY/$PROJECT:$TAG" --push "$ROOT"

docker buildx build --platform linux/amd64 --provenance=false \
  -f "$ROOT/Dockerfile.lambda" -t "$REGISTRY/$PROJECT-lambda:$TAG" --push "$ROOT"
