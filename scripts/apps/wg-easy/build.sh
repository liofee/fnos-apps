#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/meta.env"

VERSION="${VERSION:-latest}"
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

mkdir -p "${WORK_DIR}/docker"
cp "${SCRIPT_DIR}/../../../apps/wg-easy/fnos/docker/docker-compose.yaml" "${WORK_DIR}/docker/"
sed -i.bak "s/\${VERSION}/${VERSION}/g" "${WORK_DIR}/docker/docker-compose.yaml"
rm -f "${WORK_DIR}/docker/docker-compose.yaml.bak"

# Seed .env so docker compose validates BEFORE service_postinst runs.
# docker-compose.yaml declares env_file: [.env] which requires the file to
# exist at compose validation time. service_postinst overwrites with wizard values.
cat > "${WORK_DIR}/docker/.env" <<'EOF'
# Seed file shipped in fpk. Will be overwritten by service_postinst.
EOF

cp -a "${SCRIPT_DIR}/../../../apps/wg-easy/fnos/ui" "${WORK_DIR}/ui"

cd "${WORK_DIR}"
tar czf "${SCRIPT_DIR}/../../../app.tgz" docker/ ui/

echo "Built app.tgz for wg-easy ${VERSION}"
