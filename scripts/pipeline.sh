#!/usr/bin/env bash
set -euo pipefail

REGISTRY="${REGISTRY:-192.168.56.10:5000}"
IMAGE_NAME="${IMAGE_NAME:-my-app}"
DOCKERFILE="${1:-Dockerfile}"
TAG="${2:-latest}"
SEVERITY="${SEVERITY:-CRITICAL,HIGH}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${ROOT_DIR}/app"
REPORT_DIR="${ROOT_DIR}/reports"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"

mkdir -p "${REPORT_DIR}"

step() {
  printf '\n==> %s\n' "$*"
}

fail() {
  printf '\nPIPELINE FAILED: %s\n' "$*" >&2
  exit 1
}

step "1/5 Тесты"
(
  cd "${APP_DIR}"
  python -m pytest -q
) || fail "тесты не прошли"

step "2/5 Проверка Dockerfile"
trivy config \
  --file-patterns "dockerfile:${DOCKERFILE}" \
  --exit-code 1 \
  --severity "${SEVERITY}" \
  "${APP_DIR}/${DOCKERFILE}" \
  || fail "проверка Dockerfile не пройдена"

step "3/5 Сборка"
docker build --pull \
  -t "${IMAGE}" \
  -f "${APP_DIR}/${DOCKERFILE}" \
  "${APP_DIR}" \
  || fail "сборка не удалась"

step "4/5 Сканирование"

trivy image \
  --format json \
  -o "${REPORT_DIR}/${IMAGE_NAME}-${TAG}.json" \
  "${IMAGE}" \
  || fail "не удалось сохранить отчёт"

trivy image \
  --exit-code 1 \
  --ignore-unfixed \
  --severity "${SEVERITY}" \
  "${IMAGE}" \
  || fail "сканирование образа не пройдено"

step "5/5 Публикация"
docker push "${IMAGE}" \
  || fail "публикация не удалась"

printf '\nPIPELINE OK: %s опубликован\n' "${IMAGE}"