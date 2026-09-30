#!/bin/bash
# Builds the chart-assignment-controller image for the host CPU and imports it
# into k3s. CORE_COMMIT must match CHART_ASSIGNMENT_CONTROLLER_VERSION in
# intrinsic-core's intrinsic_runtime/setup_k3s.sh (0.1.0-<commit>).
set -euo pipefail
cd "$(dirname "$0")"
CORE_COMMIT="${CORE_COMMIT:-cf378be}"
TAG="localhost/chart-assignment-controller:${CORE_COMMIT}"
podman build --build-arg CORE_COMMIT="${CORE_COMMIT}" -t "${TAG}" .
podman save --format oci-archive "${TAG}" | sudo k3s ctr images import -
echo "${TAG}"
