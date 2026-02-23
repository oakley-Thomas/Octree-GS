#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
ENV_FILE="${SCRIPT_DIR}/.env"

DEFAULT_OUTPUT_ROOT="${SCRIPT_DIR}/runs"
DEFAULT_FPS=""

usage() {
  cat <<'EOF'
Usage:
  bash docker/run_multi_video_pipeline.sh [--fps N] [--output-root DIR] <video-or-directory> [more videos/dirs...]

Examples:
  bash docker/run_multi_video_pipeline.sh /data/clip1.mp4 "/data/My Clip.mov"
  bash docker/run_multi_video_pipeline.sh --fps 2 --output-root /tmp/octree-runs /data/videos

Notes:
  - Directories are scanned non-recursively for common video extensions.
  - One output folder is created per video.
  - The pipeline runs sequentially and stops on the first failure.
EOF
}

abs_path() {
  local path="$1"
  if [[ -d "$path" ]]; then
    (cd "$path" && pwd -P)
  else
    local dir base
    dir="$(cd "$(dirname "$path")" && pwd -P)"
    base="$(basename "$path")"
    printf '%s/%s\n' "$dir" "$base"
  fi
}

is_video_file() {
  local file="${1,,}"
  case "$file" in
    *.mp4|*.mov|*.mkv|*.avi|*.m4v|*.webm) return 0 ;;
    *) return 1 ;;
  esac
}

slugify() {
  local input="$1"
  local slug
  slug="$(printf '%s' "$input" | tr -cs '[:alnum:]' '_' | sed 's/^_\\{1,\\}//; s/_\\{1,\\}$//')"
  if [[ -z "$slug" ]]; then
    slug="video"
  fi
  printf '%s\n' "$slug"
}

unique_dir_for() {
  local base_dir="$1"
  if [[ ! -e "$base_dir" ]]; then
    printf '%s\n' "$base_dir"
    return
  fi

  local idx=2
  while [[ -e "${base_dir}_${idx}" ]]; do
    ((idx++))
  done
  printf '%s_%d\n' "$base_dir" "$idx"
}

FPS_OVERRIDE="$DEFAULT_FPS"
OUTPUT_ROOT="$DEFAULT_OUTPUT_ROOT"
declare -a INPUTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --fps)
      shift
      [[ $# -gt 0 ]] || { echo "Missing value for --fps" >&2; exit 1; }
      FPS_OVERRIDE="$1"
      ;;
    --output-root)
      shift
      [[ $# -gt 0 ]] || { echo "Missing value for --output-root" >&2; exit 1; }
      OUTPUT_ROOT="$1"
      ;;
    --*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      INPUTS+=("$1")
      ;;
  esac
  shift
done

if [[ ${#INPUTS[@]} -eq 0 ]]; then
  usage >&2
  exit 1
fi

mkdir -p "$OUTPUT_ROOT"
OUTPUT_ROOT="$(abs_path "$OUTPUT_ROOT")"

declare -a VIDEOS=()
for input in "${INPUTS[@]}"; do
  if [[ -d "$input" ]]; then
    while IFS= read -r -d '' file; do
      VIDEOS+=("$file")
    done < <(find "$input" -maxdepth 1 -type f \( \
      -iname '*.mp4' -o -iname '*.mov' -o -iname '*.mkv' -o -iname '*.avi' -o -iname '*.m4v' -o -iname '*.webm' \
    \) -print0 | sort -z)
  elif [[ -f "$input" ]]; then
    if is_video_file "$input"; then
      VIDEOS+=("$input")
    else
      echo "Skipping non-video file: $input" >&2
    fi
  else
    echo "Input not found: $input" >&2
    exit 1
  fi
done

if [[ ${#VIDEOS[@]} -eq 0 ]]; then
  echo "No video files found." >&2
  exit 1
fi

echo "Found ${#VIDEOS[@]} video(s). Output root: ${OUTPUT_ROOT}"

run_pipeline() {
  local video_path="$1"
  local video_abs video_dir video_file stem slug run_dir run_name project_name
  video_abs="$(abs_path "$video_path")"
  video_dir="$(dirname "$video_abs")"
  video_file="$(basename "$video_abs")"
  stem="${video_file%.*}"
  slug="$(slugify "$stem")"
  run_dir="$(unique_dir_for "${OUTPUT_ROOT}/${slug}")"
  run_name="$(basename "$run_dir")"
  project_name="octreegs_${run_name}"
  project_name="${project_name:0:55}"

  mkdir -p "${run_dir}/frames" "${run_dir}/dataset" "${run_dir}/splat"

  echo
  echo "=== Processing: ${video_file} ==="
  echo "Video: ${video_abs}"
  echo "Run dir: ${run_dir}"
  echo "Project: ${project_name}"

  local -a compose_cmd=(
    docker compose
    --env-file "$ENV_FILE"
    -f "$COMPOSE_FILE"
    -p "$project_name"
  )
  local -a compose_env=(
    env
    INPUT_VIDEO_DIR="$video_dir"
    INPUT_VIDEO_FILE="$video_file"
    RUN_OUTPUT_DIR="$run_dir"
  )
  if [[ -n "$FPS_OVERRIDE" ]]; then
    compose_env+=(FPS="$FPS_OVERRIDE")
  fi

  local up_rc=0
  set +e
  "${compose_env[@]}" "${compose_cmd[@]}" up --abort-on-container-exit --exit-code-from octree-gs
  up_rc=$?
  "${compose_env[@]}" "${compose_cmd[@]}" down --remove-orphans >/dev/null 2>&1 || true
  set -e

  if [[ $up_rc -ne 0 ]]; then
    echo "Pipeline failed for ${video_file} (exit code ${up_rc})." >&2
    return "$up_rc"
  fi

  echo "Completed: ${video_file}"
  echo "Outputs: ${run_dir}/splat"
}

for video in "${VIDEOS[@]}"; do
  run_pipeline "$video"
done

echo
echo "All videos processed successfully."
