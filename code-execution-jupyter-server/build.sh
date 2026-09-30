#!/bin/bash
# Builds the Jupyter server image for the host CPU and imports it into k3s.
set -euo pipefail
cd "$(dirname "$0")"
TAG="localhost/code-execution-jupyter-server:arm64"
podman build -t "${TAG}" .
podman save --format oci-archive "${TAG}" | sudo k3s ctr -n k8s.io images import -
echo "${TAG}"
