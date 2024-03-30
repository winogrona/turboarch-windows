#!/bin/bash

export SOURCE PROJECT_ROOT

SOURCE="$(realpath "$0")"
PROJECT_ROOT="$(dirname "$SOURCE")"

source "$PROJECT_ROOT/common.sh"
source "$PROJECT_ROOT/build_functions.sh"

if [[ -z "$1" ]]; then
  fatal_error "usage: $0 <output directory>" 2
fi

export output_dir="$1"

# shellcheck disable=1091
source "$PROJECT_ROOT/turboarch.conf"

#setup_tmpfs
#setup_root "${PACKAGE[@]}"

export base_path="/var/tmp/archbase"

trap 'fatal_error "Received SIGINT"' SIGINT

#shellcheck disable=2154
# export_root "$output_dir/00_base.tar.gz"

for overlay in "${OVERLAYS[@]}"; do
  create_overlay "$PROJECT_ROOT/overlays/$overlay"
done

# umount_root
