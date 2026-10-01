# Intrinsic Flowstate and OMTS on arm64: start here

Everything needed to build and run Intrinsic Core and the Open Machine
Tending Solution (OMTS) natively on arm64 Linux hosts (no emulation), in
simulation with Gazebo. The work is spread over these repositories; each
fork's default branch is its arm64 branch:

| Repository | Branch | What it adds |
| :--- | :--- | :--- |
| [jkammerl/intrinsic-core](https://github.com/jkammerl/intrinsic-core) (fork of intrinsic-ai/intrinsic-core) | `arm64-20260922.0` | Release 20260922.0, the core version OMTS uses, plus native arm64 builds, native images (zenoh router, Jupyter), arm64 Gazebo, the ONNX Runtime server instead of Triton (no GPU needed), and fixes. The guide is `developer_resources/guides/run_on_arm64.md`. |
| | `arm64-main` | The same changes on top of upstream `main`. |
| [jkammerl/intrinsic-omts](https://github.com/jkammerl/intrinsic-omts) (fork) | `arm64` | Builds on arm64, FoundationPose on CPUs, the Lab BB-01 cell fixes. `arm64.bazelrc.example` points the build at the pieces below. |
| [jkammerl/sdk-ros](https://github.com/jkammerl/sdk-ros) (fork) | `arm64/build-on-arm64` | Builds on arm64; the ROS bridge publishes complete workcell markers. |
| [jkammerl/intrinsic-ros-camera-drivers](https://github.com/jkammerl/intrinsic-ros-camera-drivers) (fork) | `arm64/orbbec-runtime-libs` | The Orbbec driver image's missing runtime libraries. |
| [jkammerl/hande-gripper](https://github.com/jkammerl/hande-gripper) | `master` | Native replacements for the Robotiq Hand-E gripper service and skill (their bundles ship amd64-only binaries without sources). |
| this repository | `master` | Native images for the remaining amd64-only images, and `make_omts_bundles.sh`, which puts native images into OMTS's asset bundles. |
| [jkammerl/intrinsics-litert-pose-estimation](https://github.com/jkammerl/intrinsics-litert-pose-estimation) | `main` | Optional: the OMTS pose estimator's networks on LiteRT (GPU via WebGPU, or CPU), as a C++ library, ROS 2 node, Intrinsic service image and web demo. |

Tested on an arm64 VM (6 cores, 30 GB RAM, 250 GB disk, Ubuntu 26.04, no
GPU). Builds need about 16 GB of RAM and 100 GB of disk.

## 1. Check out

```bash
mkdir -p ~/arm64 && cd ~/arm64
git clone -b arm64-20260922.0 https://github.com/jkammerl/intrinsic-core
git clone -b arm64 https://github.com/jkammerl/intrinsic-omts
git clone -b arm64/build-on-arm64 https://github.com/jkammerl/sdk-ros
mkdir -p ros_ws/src && git clone -b arm64/orbbec-runtime-libs \
    https://github.com/jkammerl/intrinsic-ros-camera-drivers \
    ros_ws/src/flowstate-ros-camera-drivers
git clone https://github.com/jkammerl/hande-gripper
git clone https://github.com/jkammerl/native-images
```

## 2. Intrinsic Core

Follow `intrinsic-core/developer_resources/guides/run_on_arm64.md`: host
setup (k3s), then deploy the base platform:

```bash
cd ~/arm64/intrinsic-core
bazel run --config=arm64 //intrinsic_runtime/kubernetes/intrinsic_base:intrinsic-base
```

`setup_k3s.sh` installs the cloud-robotics chart-assignment-controller, which
is published for amd64 only. Replace it with a native build:

```bash
~/arm64/native-images/chart-assignment-controller/build.sh
helm upgrade chart-assignment-controller \
    oci://us-docker.pkg.dev/cloud-robotics-releases/charts/chart-assignment-controller \
    --version 0.1.0-cf378be -n default --reuse-values --set webhook.enabled=false \
    --set image.repository=localhost/chart-assignment-controller \
    --set image.digest= --set image.tag=cf378be --set image.pullPolicy=Never --wait
```

## 3. Native images for OMTS's asset bundles

OMTS downloads four prebuilt asset bundles whose images are amd64-only.
Build native images, then put them into copies of the bundles:

```bash
cd ~/arm64
# ROS 2 + Intrinsic SDK underlay, then the Flowstate ROS bridge on top of it.
mkdir -p sdk_ws/src && cp -r sdk-ros sdk_ws/src/sdk-ros
podman build -f native-images/sdk-ros-underlay/Containerfile \
    -t localhost/sdk-ros-underlay:lyrical sdk_ws
podman build -f native-images/flowstate-ros-bridge/Containerfile \
    -t localhost/flowstate-ros-bridge:arm64 sdk-ros
# Orbbec Gemini camera driver.
(cd ros_ws && podman build \
    -f src/flowstate-ros-camera-drivers/flowstate_orbbec/flowstate/Dockerfile.flowstate_service \
    --build-arg SERVICE_PACKAGE=flowstate_orbbec \
    --build-arg SERVICE_NAME=orbbec_gemini_driver \
    -t localhost/orbbec-gemini-driver:arm64 .)
# Robotiq Hand-E gripper service (simulation and real) and skill.
(cd hande-gripper \
  && podman build -f image/service.Containerfile --build-arg VARIANT=sim \
       -t localhost/hande-gripper-service:sim . \
  && podman build -f image/service.Containerfile --build-arg VARIANT=real \
       -t localhost/hande-gripper-service:real . \
  && podman build -f image/skill.Containerfile -t localhost/gripper-cmd-skill:arm64 .)

# The original bundles (OMTS release 20260922.0), then the native ones.
mkdir -p orig_bundles && for b in flowstate_ros_bridge hand_e_gripper_cmd_skill \
    hand_e_gripper_service orbbec_gemini_driver; do
  curl -fsSL -o orig_bundles/$b.bundle.tar \
    https://github.com/intrinsic-ai/intrinsic-omts/releases/download/20260922.0/$b.bundle.tar
done
native-images/make_omts_bundles.sh orig_bundles native_bundles
```

The underlay takes a few hours to build; the other images minutes.

## 4. OMTS

```bash
cd ~/arm64/intrinsic-omts
sed "s|ARM64_DIR|$HOME/arm64|g" arm64.bazelrc.example > user.bazelrc
bazel run --config=lab_bb_01 //:omts_solution -- --address localhost:17080 --operation_mode=sim
bazel run --config=lab_bb_01 //tools/world:apply_scene_updates -- \
    --address=localhost:17080 --reset_sim --update_init_world --files \
    configs/lab_bb_01/ur_module.attachments.updates.pbtxt \
    configs/lab_bb_01/scene.updates.pbtxt \
    configs/lab_bb_01/align_robot.updates.pbtxt \
    configs/lab_bb_01/orbbec_gemini.updates.pbtxt
bazel run --config=lab_bb_01 //tools/pose_estimation:register_using_train_service -- \
    --address=localhost:17080 --refinement_iters=6 \
    --confidence_threshold=0.6 --visibility_threshold=0.6
bazel run --config=lab_bb_01 //src:omts_app -- --address=localhost:17080 \
    --config=configs/lab_bb_01/app_config.yaml --num_cycles=1
```

Watch it in Gazebo (`GZ_PARTITION=intrinsic_sim gz sim -g`) or RViz.

## Images in this repository

| Directory | Replaces | Use |
| :--- | :--- | :--- |
| `sdk-ros-underlay` | the underlay stage of sdk-ros's `service.Dockerfile` | Base of the ROS bridge image (step 3). |
| `flowstate-ros-bridge` | the `flowstate_ros_bridge` bundle's image | Step 3. |
| `chart-assignment-controller` | `gcr.io/cloud-robotics-releases/chart-assignment-controller` (0.1.0-cf378be) | `build.sh`, then `helm upgrade` (step 2). |
| `code-execution-jupyter-server` | `ghcr.io/intrinsic-ai/code-execution-jupyter-server@sha256:e14b4e15...` | intrinsic-core value `code_execution_jupyter_image` |

Build with `podman build`, then import into k3s where needed:
`podman save --format oci-archive <tag> | sudo k3s ctr -n k8s.io images import -`
