# Native arm64 builds of amd64-only images

Recipes for images that intrinsic-core deploys but that are published for
amd64 only, so that arm64 hosts run them without emulation.

| Directory | Replaces | Deployed via |
|---|---|---|
| `chart-assignment-controller` | `gcr.io/cloud-robotics-releases/chart-assignment-controller` (0.1.0-cf378be) | `helm upgrade ... --set image.repository=localhost/chart-assignment-controller --set image.tag=cf378be --set image.digest= --set image.pullPolicy=Never` |
| `code-execution-jupyter-server` | `ghcr.io/intrinsic-ai/code-execution-jupyter-server@sha256:e14b4e15...` | intrinsic-core value `code_execution_jupyter_image` |

Build with `podman build`, then import into k3s:
`podman save --format oci-archive <tag> | sudo k3s ctr -n k8s.io images import -`
