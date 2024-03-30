export PROJECT_ROOT
PROJECT_ROOT="$(dirname "$0")"

source "$PROJECT_ROOT/common.sh"
source "$PROJECT_ROOT/builder_functions.sh"

BUILDER_VERSION="0.1"
CONFIG_PATH="$PROJECT_ROOT/turboarch.conf"

print_usage() {
  cat <<EOF
turboarch builder v$BUILDER_VERSION
usage: $0 <export path> [options]

   Options:
    -K              Don't delete the base filesystem after completing
                    (or failing) the installation.
    -B <base path>  Use the base filesystem at <base path> instead of
                    creating a new one.
    -O <olay name>  Build only a specific overlay.
    -e <export dir> Export directory.
EOF
}

while getopts ":c:e:hKB:O:E" opt; do
  case "$opt" in
    K)
      export KEEP_BASEFS=true
    ;;
    B)
      export BASE_PATH="${OPTARG}"
      warning "Using '$BASE_PATH' as the base system path" 
    ;;
    O)
      export ONLY_OLAY="${OPTARG}"
    ;;
    h)
      print_usage
      exit
    ;;
    c)
      CONFIG_PATH="${OPTARG}"
    ;;
    e)
      EXPORT_DIR="${OPTARG}"
    ;;
    E)
      DONT_EXPORT=true
    ;;
    *)
      fatal_error "Invalid option: -$opt"
    ;;
  esac
done
# shellcheck disable=1090
source "$CONFIG_PATH" \
  || fatal_error "Failed to read the config at '$CONFIG PATH'"

set_configroot "$PROJECT_ROOT"

if [[ -z "${EXPORT_DIR:x}" ]]; then
  EXPORT_DIR="$(mktemp -p /var/tmp -dt turboarch.export.XXXXXX)"
  warning "Exporting to '$EXPORT_DIR'"
fi

set_exportdir "$EXPORT_DIR"

if [[ -n "${BASE_PATH:x}" ]]; then
  set_baseroot "$BASE_PATH"
else
  set_baseroot "$(mktemp -dt "rootfs.XXXXXX" -p /var/tmp/)"
  [[ -n "${KEEP_BASEFS:x}" ]] || defer "clear_base" "clear_baseroot"
  setup_base "${PACKAGES[@]}"
fi

[[ -z "${DONT_EXPORT:x}" ]] && export_base

destdir="$(mktemp -p /var/tmp/ -dt 'overlays.XXXXXX')"
defer 'del_destdir' "clear_olaydest"
set_olaydest "$destdir"

if [[ -n "${ONLY_OLAY:x}" ]]; then
  build_overlay "$ONLY_OLAY"
  exec_defers
  exit
fi

info "Building overlays [${OVERLAYS[*]}]"
for overlay in "${OVERLAYS[@]}"; do
  build_overlay "$overlay"
done

exec_defers
