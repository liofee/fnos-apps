#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/meta.env"

VERSION="${VERSION:-latest}"
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

mkdir -p "${WORK_DIR}/docker"
cp "${SCRIPT_DIR}/../../../apps/firefox/fnos/docker/docker-compose.yaml" "${WORK_DIR}/docker/"
sed -i "s/\${VERSION}/${VERSION}/g" "${WORK_DIR}/docker/docker-compose.yaml"

# Seed .env so docker compose validates BEFORE service_postinst runs.
# docker-compose.yaml declares env_file: [.env] which requires the file to
# exist at validation time (fnOS validates the compose file before invoking
# install hooks). service_postinst overwrites this seed with wizard values.
cat > "${WORK_DIR}/docker/.env" <<'EOF'
# Seed file shipped in fpk. Will be overwritten by service_postinst with
# wizard-supplied VNC_PASSWORD. Empty value here = no auth (default).
VNC_PASSWORD=
EOF

cp -a "${SCRIPT_DIR}/../../../apps/firefox/fnos/ui" "${WORK_DIR}/ui"

cd "${WORK_DIR}"
tar czf "${SCRIPT_DIR}/../../../app.tgz" docker/ ui/

echo "Built app.tgz for firefox ${VERSION}"
