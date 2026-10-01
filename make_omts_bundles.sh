#!/bin/bash
# Builds OMTS's prebuilt asset bundles with natively built images.
#
# Each bundle keeps the original bundle's manifest, default config and
# descriptor set, and only replaces its image tar(s) with the native image,
# saved under the same file name and tag. The bundles are written as Bazel
# repositories into OUT_DIR, for OMTS's user.bazelrc:
#   common --override_repository=+gh_release+<name>_bundle=$OUT_DIR/<name>_bundle
#
# Usage: make_omts_bundles.sh <original bundles dir> <out dir> [bundle ...]
#   The original bundles dir holds <name>.bundle.tar (e.g. the gh_release
#   repositories' files).
set -euo pipefail

ORIG_DIR="$1"
OUT_DIR="$2"
shift 2

# bundle name -> "image tar in the bundle=native image=tag in the image tar" ...
declare -A IMAGES=(
  [hand_e_gripper_service]="hande-gripper-aquarium-hande-gripper.launch.xml.tar=localhost/hande-gripper-service:real=localhost/hande-gripper-aquarium-hande-gripper.launch.xml:latest hande-gripper-sim-driver-hande-gripper.launch.xml.tar=localhost/hande-gripper-service:sim=localhost/hande-gripper-sim-driver-hande-gripper.launch.xml:latest"
  [hand_e_gripper_cmd_skill]="gripper_cmd_skill.tar=localhost/gripper-cmd-skill:arm64=localhost/gripper_cmd_skill:latest"
  [flowstate_ros_bridge]="flowstate_ros_bridge.tar=localhost/flowstate-ros-bridge:arm64=flowstate_ros_bridge:flowstate_ros_bridge"
  [orbbec_gemini_driver]="orbbec_gemini_driver.tar=localhost/orbbec-gemini-driver:arm64=flowstate_orbbec:orbbec_gemini_driver"
)

bundles=("$@")
[ ${#bundles[@]} -gt 0 ] || bundles=("${!IMAGES[@]}")

for name in "${bundles[@]}"; do
  orig="${ORIG_DIR}/${name}.bundle.tar"
  repo="${OUT_DIR}/${name}_bundle"
  work=$(mktemp -d)
  echo "== ${name}"
  tar -xf "${orig}" -C "${work}"
  for spec in ${IMAGES[$name]}; do
    IFS='=' read -r file image tag <<< "${spec}"
    arch=$(podman image inspect --format '{{.Architecture}}' "${image}")
    echo "   ${file} <- ${image} (${arch})"
    rm -f "${work}/${file}"
    podman tag "${image}" "${tag}"
    podman save --format docker-archive -o "${work}/${file}" "${tag}"
  done
  mkdir -p "${repo}"
  # Same member order as the original bundle.
  (cd "${work}" && tar -cf "${repo}/${name}.bundle.tar" $(tar -tf "${orig}"))
  rm -rf "${work}"
  cat > "${repo}/BUILD.bazel" <<EOF
package(default_visibility = ["//visibility:public"])

exports_files(["${name}.bundle.tar"])

filegroup(
    name = "file",
    srcs = ["${name}.bundle.tar"],
)
EOF
  : > "${repo}/REPO.bazel"
  ls -la "${repo}/${name}.bundle.tar"
done
