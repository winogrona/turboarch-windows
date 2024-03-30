source "$PROJECT_ROOT/common.sh"

declare -Ag ON_FAILURE_MAP=()

trap 'exec_defers' SIGINT
exec_defers() {
  for expression in "${ON_FAILURE_MAP[@]}"; do
    eval "$expression"
  done
}

on_sigint() {
  warning "Caught SIGINT"
  exec_defers
  exit 2
}

fatal_error() {
  local error_text="$1" exit_code="${2:-2}"
  error "fatal: $error_text"
  exec_defers
  exit "$exit_code"
}

defer() {
  local tag="$1" expression="$2"

  ON_FAILURE_MAP["$tag"]="$expression"
}

undefer() {
  local tag="$1"

  unset "ON_FAILURE_MAP['$tag']"
}

test() {
  echo "Hello guys"
}

set_baseroot() {
  export GLOB_baseroot="$1"
}

set_olayname() {
  export GLOB_olayname="$1"
  export GLOB_olaypath="$GLOB_configroot/overlays/$GLOB_olayname"
}

set_olaypriority() {
  export GLOB_olaypriority="$1"
}

set_configroot() {
  export GLOB_configroot="$1"
}

set_olaydest() {
  export GLOB_dest="$1"
}

set_exportdir() {
  info "Exporting to '$1'"
  export GLOB_exportdir="$1"
}

setup_base() {  
  packages=("$@")

  info "Installing the base system"
  pacstrap -c "$GLOB_baseroot" "${packages[@]}" \
    || fatal_error "Failed to install the base system" "$?"
}

clear_baseroot() {
  info "Clearing the base filesystem"
  rm -rf "$GLOB_baseroot" || error "Failed to clear the base filesystem"
}

export_base() {
  info "Exporting the base system as a tar.gz archive"
  tar -cC "$GLOB_baseroot" . 2>/dev/null \
    | pv -s "$(du -bs "$GLOB_baseroot" | awk '{print $1}')" \
    | gzip \
    > "$GLOB_exportdir/00_base.tar.gz" \
    || fatal_error "Failed to export the base system" "$?"
}

add_packages() {
  local package_list=("$@")
  info "Installing packages: ${package_list[*]}"
  mapfile -t links < <(pacman \
    --root "$GLOB_baseroot" \
    --quiet \
    --noconfirm \
    --print \
    --cachedir "/ Please don't use cache /" \
    -S "${package_list[@]}") \
    || fatal_error "Failed to query packages" "$?"

  mkdir -p "$GLOB_dest/packages/"
  wget -P "$GLOB_dest/packages/" \
    --quiet \
    --show-progress \
    "${links[@]}" \
    || fatal_error "Failed to download the packages" "$?"
}

add_file() {
  local source="$1" dest="${2:-$dest}"

  if ! [[ -f "$source" ]]; then
    fatal_error "File '$source' not fount"
  fi
  
  mkdir -p "$GLOB_dest/files/$(dirname "$dest")"
  cp "$source" "$GLOB_dest/files/$dest"
}

add_services() {
  local service_names=("$@")

  for service_name in "${service_names[@]}"; do
    echo "$service_name" >> "$GLOB_dest/services"
  done
}

add_scripts() {
  local script_names=("$@")

  for script_name in "${script_names[@]}"; do
    mkdir -p "$GLOB_dest/scripts"
    if ! [[ -f "$GLOB_olaypath/scripts/$script_name" ]]; then
      fatal_error "Script '$script_name' not found"
    fi
    cp "$GLOB_olaypath/scripts/$script_name" "$GLOB_dest/scripts/" \
      || fatal_error "Failed to install the script '$script_name'"
  done
}

export_overlay() {
  info "Exporting '$GLOB_olayname' as a tar.gz archive"
  if ! tar -cC "$GLOB_dest" "." \
    | pv -s "$(du -bs "$GLOB_dest" | awk '{print $1}')" \
    | gzip \
    > "$GLOB_exportdir/${GLOB_olaypriority}_$GLOB_olayname.tar.gz"; then
    
    fatal_error "Failed to export '$GLOB_olayname'" "$?"
  fi
}

clear_olaydest() {
  info "Clearing the destination directory for '$GLOB_olayname'"
  rm -rf "$GLOB_dest" || error "Failed to clear '$GLOB_dest'"
}

shopt -s nullglob
add_files_from_dir() {
  local path="$1"
  mkdir -p "$GLOB_dest/files/"
  cp -r "$path"/* "$GLOB_dest/files/" || fatal_error "Failed to add '$path'"
}

build_overlay() {
  local olayname="$1"
  set_olayname "$olayname"

  #shellcheck disable=1091
  source "$GLOB_olaypath/overlay.conf"

  set_olaypriority "$PRIORITY"

  info "Building the overlay '$olayname'"

  set_olaydest "$(mktemp -dp /var/tmp/ -t "overlay.$olayname.XXXXX")"
  defer "clear" "clear_olaydest"

  # shellcheck disable=2153
  info "Adding packages [${PACKAGES[*]}]"
  add_packages "${PACKAGES[@]}"
  info "Adding services [${SERVICES[*]}]"
  add_services "${SERVICES[@]}"
  info "Adding scripts [${SCRIPTS[*]}]"
  add_scripts "${SCRIPTS[@]}"
  info "Adding files"
  add_files_from_dir "$GLOB_olaypath/files/"

  info "Executing hooks"
  for hook in "${HOOKS[@]}"; do
    info "==> $hook"
    #shellcheck disable=1090
    source "$GLOB_olaypath/hooks/$hook"
  done

  export_overlay

  clear_olaydest
  undefer "clear"
}
