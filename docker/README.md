# Docker Workflow for Octree-GS

This folder contains:
- `Dockerfile`: builds the `octree-gs:latest` training image.
- `docker-compose.yml`: runs a 3-stage pipeline:
  1. `ffmpeg` (extract frames from `video.mp4`)
  2. `colmap` (build SfM dataset)
  3. `octree-gs` (train model)

## Prerequisites

- Docker + Docker Compose plugin
- NVIDIA GPU with NVIDIA Container Toolkit (`--gpus all` support)

## 1) Build the Octree-GS image

From the repository root:

```bash
docker build -t octree-gs:latest -f docker/Dockerfile .
```

## 2) Configure input video path

Edit `docker/.env`:

```env
INPUT_VIDEO_PATH=/absolute/path/to/folder/that-contains-video.mp4
FPS=1
```

Notes:
- The compose file expects the input file at `/input/video.mp4`, so your host folder must contain a file named `video.mp4`.
- `FPS` controls extracted frame rate.

## 3) Run the full pipeline (ffmpeg -> colmap -> octree-gs)

From the repository root:

```bash
docker compose --env-file docker/.env -f docker/docker-compose.yml up --abort-on-container-exit
```

To stop and remove containers (keep volumes):

```bash
docker compose --env-file docker/.env -f docker/docker-compose.yml down
```

## 4) Run only one service

Run only training (skip ffmpeg/colmap):

```bash
docker compose --env-file docker/.env -f docker/docker-compose.yml up --no-deps --force-recreate octree-gs
```

Open a shell in the `octree-gs` service:

```bash
docker compose --env-file docker/.env -f docker/docker-compose.yml run --rm --no-deps octree-gs bash
```

## 5) Data persistence

Compose uses named volumes:
- `video_frames`
- `colmap_dataset`
- `gaussian_splatting_output`

These volumes persist after containers exit. They are removed only if you use `down -v` or delete volumes manually.

List actual volume names:

```bash
docker compose --env-file docker/.env -f docker/docker-compose.yml config --volumes
docker volume ls
```

Inspect the COLMAP dataset volume:

```bash
docker run --rm -it -v docker_colmap_dataset:/dataset ubuntu:22.04 bash -lc "ls -lah /dataset && ls -lah /dataset/sparse/0"
```

If your compose project name is different, replace `docker_colmap_dataset` with the real name from `docker volume ls`.
