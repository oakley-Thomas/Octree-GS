# Docker Workflow for Octree-GS

This folder contains:
- `Dockerfile`: builds the `octree-gs:latest` training image.
- `docker-compose.yml`: runs a 3-stage pipeline:
  1. `ffmpeg` (extract frames from any input video filename)
  2. `colmap` (build SfM dataset)
  3. `octree-gs` (train model)
- `run_multi_video_pipeline.sh`: runs the full pipeline for multiple videos (one command, one output folder per video)

## Prerequisites

- Docker + Docker Compose plugin
- NVIDIA GPU with NVIDIA Container Toolkit (`--gpus all` support)

## 1) Build the Octree-GS image

From the repository root:

```bash
docker build -t octree-gs:latest -f docker/Dockerfile .
```

## 2) Configure a single run (manual compose usage)

Edit `docker/.env`:

```env
INPUT_VIDEO_DIR=/absolute/path/to/folder/that-contains-the-video
INPUT_VIDEO_FILE=your_video_name.mp4
RUN_OUTPUT_DIR=/absolute/path/for/run-output
FPS=1
```

Notes:
- `INPUT_VIDEO_FILE` can be any filename (spaces are okay).
- `RUN_OUTPUT_DIR` will contain:
  - `frames/` (ffmpeg output)
  - `dataset/` (COLMAP dataset)
  - `splat/` (Octree-GS output)
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

## 4) Batch multiple videos with one command (recommended)

From the repository root:

```bash
bash docker/run_multi_video_pipeline.sh /abs/path/video1.mp4 "/abs/path/My Clip.mov" /abs/path/video3.mkv
```

You can also pass a directory to process all supported video files inside it:

```bash
bash docker/run_multi_video_pipeline.sh /abs/path/to/videos
```

Optional flags:

```bash
bash docker/run_multi_video_pipeline.sh --fps 2 --output-root /abs/path/octree-batch-runs /abs/path/to/videos
```

What the script does:
- Accepts arbitrary video filenames (no renaming to `video.mp4`)
- Creates one run folder per video under `docker/runs/` by default
- Uses a unique compose project per video to avoid container naming collisions
- Runs the pipeline sequentially and stops on the first failure

## 5) Run only one service

Run only training (skip ffmpeg/colmap):

```bash
docker compose --env-file docker/.env -f docker/docker-compose.yml up --no-deps --force-recreate octree-gs
```

Open a shell in the `octree-gs` service:

```bash
docker compose --env-file docker/.env -f docker/docker-compose.yml run --rm --no-deps octree-gs bash
```

## 6) Data persistence

Pipeline data is stored directly on the host in `RUN_OUTPUT_DIR` (or under `docker/runs/` when using the batch script). Containers can be removed with `docker compose ... down` without deleting generated files.

Inspect outputs for one run:

```bash
ls -lah /path/to/run-output
ls -lah /path/to/run-output/dataset/sparse/0
ls -lah /path/to/run-output/splat
```

If you want to rerun a video cleanly, use a new `RUN_OUTPUT_DIR` (or let the batch script create a new folder automatically).
