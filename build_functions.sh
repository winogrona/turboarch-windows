#!/bin/bash

source /opt/turboarch/common.sh

fatal_error() {
  local error_text="$1" error_code="$2"
  error "fatal: $error_text"
  mountpoint -q "$wdir" && umount_ofs
  # [[ -d "$udir" ]] && clean_udir
  exit "${error_code:-1}"
}

setup_tmpfs() {
  export base_path
  base_path="$(mktemp -d)"
  mount -t tmpfs tmpfs "$base_path" || fatal_error "Failed to mount tmpfs" "$?"
}

setup_root() {
  local packages=("$@")

  logfile="$(mktemp -t "pacstrap.XXXXXX.log" -p "$TMPDIR")"

  info "Installing the base system"
  pacstrap "$base_path" "${packages[@]}" \
    || fatal_error "Failed to setup a base filesystem" "$?"
}

export_root() {
  local export_path="$1"
  info "Exporting the rootfs archive"
  tar -cC "$base_path" . | pv -s "$(du -bs "$base_path" | awk '{print $1}')" | gzip > "$export_path" \
    || fatal_error "Failed to export the rootfs archive to '$export_path'"
}

umount_root() {
  umount "$base_path" || fatal_error "Failed to umount '$base_path'" "$?"
}

add_packages() {
  local packages=("$@") 

  logfile="$(mktemp pacman.XXXXXX.log -p "$TMPDIR")"

  arch-chroot "$wdir" mkdir -p "$install_olay_path/packages/"
  mapfile -t links < <(arch-chroot "$wdir" pacman --cachedir "/ Please don't use cache /" \
    -Sp "${packages[@]}" 2>"$logfile" \
    || fatal_error "Failed to query the packages '${packages[*]}' (pacman log in $logfile)" "$?")

  info "= Downloading packages"
  wget -P "$wdir/$install_olay_path/packages/" -q --show-progress "${links[@]}" \
    || fatal_error "Failed to download the packages" "$?"
}

setup_ofs() {
  # shellcheck disable=2154
  mount -t overlay overlay "$wdir" \
    -o "lowerdir=$base_path,upperdir=$udir,workdir=$wdir" \
    || fatal_error "Failed to mount overlayfs" "$?"
}

umount_ofs() {
  info "Unmounting overlayfs"
  umount "$wdir" || error "Failed to umount '$wdir'"
}

clean_udir() {
  info "Cleaning upperdir"
  rm -r "$udir" || error "Failed to clean '$udir'"
}

enable_service() {
  local service_name="$1"

  echo "systemctl enable '$service_name'" >> "$wdir/$install_olay_path/install.sh"
}

add_file() {
  local source="$1" dest="$2"

  [[ -z "${dest+x}" ]] && dest="$source"

  mkdir -p "$wdir/$(dirname "$dest")"
  cp "$source" "$wdir/$dest" || fatal_error "Failed to copy '$source' to '$dest'"
}

add_install_script() {
  local script="$1"

  add_file "$olay_path/scripts/$script" "$install_olay_path/scripts/$script"
}

create_overlay() {
  export olay_path="$1" wdir udir olay_name base_path install_olay_path
  
  udir="$(mktemp -dp /var/tmp/)"
  wdir="$(mktemp -dp /var/tmp/)"

  setup_ofs

  # shellcheck disable=SC1091
  source "$olay_path/overlay.conf"
  olay_name="$NAME"
  install_olay_path="$TA_ROOT/overlays/${PRIORITY}_$NAME"

  # shellcheck disable=2153
  info "Adding packages (${PACKAGES[*]})"
  # shellcheck disable=2153
  add_packages "${PACKAGES[@]}"

  info "Adding services"
  for service in "${SERVICES[@]}"; do
    info " => [$service]"
    enable_service "$service"
  done

  info "Running hooks"
  for hook in "${HOOKS[@]}"; do
    info " => [$hook]"
    # shellcheck disable=1090
    source "$olay_path/hooks/$hook"
  done

  info "Adding install scripts"
  for script in "${INSTALL_SCRIPTS[@]}"; do
    info " => [$script]"
    add_install_script "$script"
  done

  umount_ofs || error "Failed to umount overlayfs"

  # shellcheck disable=2154
  info "Exporting as '$output_dir/${PRIORITY}_$NAME.tar.gz'"
  tar -cC "$udir" . | pv -s "$(du -bs "$udir" | awk '{print $1}')" \
    | gzip > "$output_dir/${PRIORITY}_$NAME.tar.gz" \
    || fatal_error "Failed to create an archive"

  clean_udir
}
