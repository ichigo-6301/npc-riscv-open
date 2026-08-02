#!/usr/bin/env bash
set -euo pipefail

: "${NPC_ASIC_ROOT:?Missing NPC_ASIC_ROOT}"
: "${NPC_ASIC_BUILD_ROOT:?Missing NPC_ASIC_BUILD_ROOT}"
: "${NPC_ASIC_TOP:?Missing NPC_ASIC_TOP}"
: "${NPC_ASIC_DESIGN_NICKNAME:?Missing NPC_ASIC_DESIGN_NICKNAME}"
: "${NPC_ASIC_MAPPED_NETLIST:?Missing NPC_ASIC_MAPPED_NETLIST}"
: "${NPC_ASIC_PNR_SDC:?Missing NPC_ASIC_PNR_SDC}"
: "${NPC_ASIC_PNR_PERIOD_NS:?Missing NPC_ASIC_PNR_PERIOD_NS}"
: "${NPC_ASIC_DIE_AREA:?Missing NPC_ASIC_DIE_AREA}"
: "${NPC_ASIC_CORE_AREA:?Missing NPC_ASIC_CORE_AREA}"
: "${NPC_ASIC_PLACE_DENSITY:?Missing NPC_ASIC_PLACE_DENSITY}"
: "${NPC_ASIC_ORFS_IMAGE:?Missing NPC_ASIC_ORFS_IMAGE}"
: "${NPC_ASIC_ORFS_IMAGE_DIGEST:?Missing NPC_ASIC_ORFS_IMAGE_DIGEST}"
: "${NPC_ASIC_ORFS_COMMIT:?Missing NPC_ASIC_ORFS_COMMIT}"
: "${NPC_ASIC_MEMORY_MODE:?Missing NPC_ASIC_MEMORY_MODE}"
: "${NPC_ASIC_EXPECTED_MACRO_COUNT:?Missing NPC_ASIC_EXPECTED_MACRO_COUNT}"
: "${NPC_ASIC_HOLD_SLACK_MARGIN:?Missing NPC_ASIC_HOLD_SLACK_MARGIN}"
: "${NPC_ASIC_PRE_GLOBAL_ROUTE_TCL:?Missing NPC_ASIC_PRE_GLOBAL_ROUTE_TCL}"
: "${NPC_ASIC_CONSTANT_NET_REPORT:?Missing NPC_ASIC_CONSTANT_NET_REPORT}"

case "$NPC_ASIC_MEMORY_MODE" in
  registers)
    test "$NPC_ASIC_EXPECTED_MACRO_COUNT" = 0 || {
      echo "Register mode requires zero macros" >&2; exit 2;
    }
    ;;
  sram)
    test "$NPC_ASIC_EXPECTED_MACRO_COUNT" = 4 || {
      echo "D8 SRAM mode requires four macros" >&2; exit 2;
    }
    for name in NPC_ASIC_MACRO_LEF_COUNT NPC_ASIC_MACRO_LIB_COUNT \
                NPC_ASIC_MACRO_GDS_COUNT; do
      [[ "${!name:-}" =~ ^[1-9][0-9]*$ ]] || {
        echo "Missing or malformed $name for SRAM mode" >&2; exit 2;
      }
    done
    for name in NPC_ASIC_MACRO_PLACEMENT_TCL NPC_ASIC_MACRO_PLACEMENT_REPORT \
                NPC_ASIC_PRE_PDN_TCL; do
      test -n "${!name:-}" || { echo "Missing $name for SRAM mode" >&2; exit 2; }
    done
    ;;
  *) echo "Unsupported memory mode: $NPC_ASIC_MEMORY_MODE" >&2; exit 2 ;;
esac

if [[ ! "$NPC_ASIC_ORFS_IMAGE_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "NPC_ASIC_ORFS_IMAGE_DIGEST must be a full sha256 digest" >&2
  exit 2
fi
case "$NPC_ASIC_ORFS_IMAGE" in
  ?*"@$NPC_ASIC_ORFS_IMAGE_DIGEST") ;;
  *) echo "NPC_ASIC_ORFS_IMAGE does not match the tracked repository digest" >&2; exit 2 ;;
esac
if [[ ! "$NPC_ASIC_ORFS_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "NPC_ASIC_ORFS_COMMIT must be a full lowercase Git commit" >&2
  exit 2
fi

for path in "$NPC_ASIC_MAPPED_NETLIST" "$NPC_ASIC_PNR_SDC"; do
  test -s "$path" || { echo "Missing P&R input: $path" >&2; exit 2; }
done
test -s "$NPC_ASIC_PRE_GLOBAL_ROUTE_TCL" || {
  echo "Missing DC constant-net normalization hook: $NPC_ASIC_PRE_GLOBAL_ROUTE_TCL" >&2
  exit 2
}

docker_tool=${NPC_ASIC_DOCKER:-docker}
work_home="$NPC_ASIC_BUILD_ROOT/orfs"
handoff="$NPC_ASIC_BUILD_ROOT/handoff"
mkdir -p "$work_home" "$handoff"

root_real=$(realpath "$NPC_ASIC_ROOT")
build_real=$(realpath "$NPC_ASIC_BUILD_ROOT")
case "$build_real" in
  "$root_real"/*) ;;
  *) echo "NPC_ASIC_BUILD_ROOT must be below NPC_ASIC_ROOT for container handoff" >&2; exit 2 ;;
esac
build_in_container="/npc/${build_real#"$root_real"/}"
orfs_identity_report="$NPC_ASIC_BUILD_ROOT/orfs_commit.txt"
orfs_identity_container="$build_in_container/orfs_commit.txt"
test ! -e "$orfs_identity_report" || {
  echo "Refusing pre-existing ORFS runtime identity report" >&2
  exit 2
}
netlist_real=$(realpath "$NPC_ASIC_MAPPED_NETLIST")
sdc_real=$(realpath "$NPC_ASIC_PNR_SDC")
for path in "$netlist_real" "$sdc_real"; do
  case "$path" in
    "$root_real"/*) ;;
    *) echo "Container input must be below NPC_ASIC_ROOT: $path" >&2; exit 2 ;;
  esac
done

container_path() {
  local path_real
  path_real=$(realpath -m "$1")
  case "$path_real" in
    "$root_real"/*) printf '/npc/%s' "${path_real#"$root_real"/}" ;;
    *) echo "Container input must be below NPC_ASIC_ROOT: $path_real" >&2; return 2 ;;
  esac
}

container_indexed_list() {
  local prefix=$1 count=$2 output_variable=$3
  local result="" path path_real container_view variable index
  local -a paths=()
  [[ "$count" =~ ^[0-9]+$ ]] || {
    echo "Malformed macro-view count for $prefix: $count" >&2; return 2;
  }
  for ((index = 0; index < count; index++)); do
    variable="${prefix}_${index}"
    path=${!variable:-}
    test -n "$path" || { echo "Missing indexed macro view: $variable" >&2; return 2; }
    paths+=("$path")
  done
  for ((index = 0; index < ${#paths[@]}; index++)); do
    path=${paths[$index]}
    test -s "$path" || { echo "Missing macro view: $path" >&2; return 2; }
    path_real=$(realpath "$path")
    case "$path_real" in
      "$root_real"/*) ;;
      *) echo "Container input must be below NPC_ASIC_ROOT: $path_real" >&2; return 2 ;;
    esac
    container_view="/npc_macro_views/${prefix}_${index}"
    macro_view_mounts+=(-v "$path_real:$container_view:ro")
    result="${result:+$result }$container_view"
  done
  printf -v "$output_variable" '%s' "$result"
}

macro_view_mounts=()
macro_lefs_container=""
macro_libs_container=""
macro_gds_container=""
container_indexed_list NPC_ASIC_MACRO_LEF "${NPC_ASIC_MACRO_LEF_COUNT:-0}" macro_lefs_container
container_indexed_list NPC_ASIC_MACRO_LIB "${NPC_ASIC_MACRO_LIB_COUNT:-0}" macro_libs_container
container_indexed_list NPC_ASIC_MACRO_GDS "${NPC_ASIC_MACRO_GDS_COUNT:-0}" macro_gds_container
macro_placement_container=""
macro_report_container=""
pre_pdn_container=""
pre_global_route_container=$(container_path "$NPC_ASIC_PRE_GLOBAL_ROUTE_TCL")
constant_net_report_container=$(container_path "$NPC_ASIC_CONSTANT_NET_REPORT")
if test "$NPC_ASIC_MEMORY_MODE" = sram; then
  macro_placement_container=$(container_path "$NPC_ASIC_MACRO_PLACEMENT_TCL")
  macro_report_container=$(container_path "$NPC_ASIC_MACRO_PLACEMENT_REPORT")
  pre_pdn_container=$(container_path "$NPC_ASIC_PRE_PDN_TCL")
fi

uid=$(id -u)
gid=$(id -g)
results_dir="$work_home/results/nangate45/$NPC_ASIC_DESIGN_NICKNAME/base"

"$docker_tool" run --rm \
  -u "$uid:$gid" \
  -v "$root_real:/npc" \
  "${macro_view_mounts[@]}" \
  -e NPC_ASIC_DESIGN_NICKNAME="$NPC_ASIC_DESIGN_NICKNAME" \
  -e NPC_ASIC_TOP="$NPC_ASIC_TOP" \
  -e NPC_ASIC_MAPPED_NETLIST="/npc/${netlist_real#"$root_real"/}" \
  -e NPC_ASIC_PNR_SDC="/npc/${sdc_real#"$root_real"/}" \
  -e NPC_ASIC_DIE_AREA="$NPC_ASIC_DIE_AREA" \
  -e NPC_ASIC_CORE_AREA="$NPC_ASIC_CORE_AREA" \
  -e NPC_ASIC_PLACE_DENSITY="$NPC_ASIC_PLACE_DENSITY" \
  -e NPC_ASIC_MEMORY_MODE="$NPC_ASIC_MEMORY_MODE" \
  -e NPC_ASIC_EXPECTED_MACRO_COUNT="$NPC_ASIC_EXPECTED_MACRO_COUNT" \
  -e NPC_ASIC_MACRO_LEFS="$macro_lefs_container" \
  -e NPC_ASIC_MACRO_LIBS="$macro_libs_container" \
  -e NPC_ASIC_MACRO_GDS="$macro_gds_container" \
  -e NPC_ASIC_MACRO_PLACEMENT_TCL="$macro_placement_container" \
  -e NPC_ASIC_MACRO_PLACEMENT_REPORT="$macro_report_container" \
  -e NPC_ASIC_PRE_PDN_TCL="$pre_pdn_container" \
  -e NPC_ASIC_PRE_GLOBAL_ROUTE_TCL="$pre_global_route_container" \
  -e NPC_ASIC_CONSTANT_NET_REPORT="$constant_net_report_container" \
  -e NPC_ASIC_MACRO_REFS="${NPC_ASIC_MACRO_REFS:-}" \
  -e NPC_ASIC_HOLD_SLACK_MARGIN="$NPC_ASIC_HOLD_SLACK_MARGIN" \
  -e NPC_ASIC_ORFS_COMMIT="$NPC_ASIC_ORFS_COMMIT" \
  -e NPC_ASIC_ORFS_IDENTITY_REPORT="$orfs_identity_container" \
  -e NPC_ASIC_ORFS_WORK_HOME="$build_in_container/orfs" \
  -w /OpenROAD-flow-scripts/flow \
  "$NPC_ASIC_ORFS_IMAGE" \
  bash -lc '
    set -eo pipefail
    actual_orfs_commit=not_embedded
    orfs_commit_verification=image_digest_bound_no_vcs_metadata
    if test -e /OpenROAD-flow-scripts/.git || test -L /OpenROAD-flow-scripts/.git; then
      if ! detected_orfs_commit=$(git -c safe.directory=/OpenROAD-flow-scripts \
          -C /OpenROAD-flow-scripts rev-parse --verify HEAD 2>/dev/null); then
        echo "ORFS VCS metadata is present but HEAD verification failed" >&2
        exit 2
      fi
      if test "$detected_orfs_commit" != "$NPC_ASIC_ORFS_COMMIT"; then
        echo "ORFS commit mismatch: expected $NPC_ASIC_ORFS_COMMIT, got $detected_orfs_commit" >&2
        exit 2
      fi
      actual_orfs_commit=$detected_orfs_commit
      orfs_commit_verification=git_head
    fi
    {
      printf "actual_commit=%s\n" "$actual_orfs_commit"
      printf "verification=%s\n" "$orfs_commit_verification"
    } > "$NPC_ASIC_ORFS_IDENTITY_REPORT"
    source /OpenROAD-flow-scripts/env.sh
    make DESIGN_CONFIG=/npc/flows/asic/openroad/config.mk \
      WORK_HOME="$NPC_ASIC_ORFS_WORK_HOME"
  '

test -s "$orfs_identity_report" || {
  echo "Missing ORFS runtime identity report" >&2
  exit 2
}
orfs_actual_commit=$(sed -n 's/^actual_commit=//p' "$orfs_identity_report")
orfs_commit_verification=$(sed -n 's/^verification=//p' "$orfs_identity_report")
case "$orfs_commit_verification" in
  git_head)
    test "$orfs_actual_commit" = "$NPC_ASIC_ORFS_COMMIT" || {
      echo "ORFS runtime Git identity report mismatch" >&2
      exit 2
    }
    ;;
  image_digest_bound_no_vcs_metadata)
    test "$orfs_actual_commit" = not_embedded || {
      echo "ORFS digest-bound identity report mismatch" >&2
      exit 2
    }
    ;;
  *) echo "Malformed ORFS runtime identity report" >&2; exit 2 ;;
esac

for artifact in 1_2_yosys.v 6_final.odb 6_final.def 6_final.v 6_final.sdc 6_final.spef 6_final.gds; do
  test -s "$results_dir/$artifact" || {
    echo "Missing ORFS final artifact: $results_dir/$artifact" >&2
    exit 2
  }
done

test -s "$NPC_ASIC_CONSTANT_NET_REPORT" || {
  echo "Missing DC constant-net normalization report" >&2
  exit 2
}

if test "$NPC_ASIC_EXPECTED_MACRO_COUNT" -gt 0; then
  test -s "$NPC_ASIC_MACRO_PLACEMENT_REPORT" || {
    echo "Missing macro placement report" >&2; exit 2;
  }
  placed_count=$(grep -c '^instance=' "$NPC_ASIC_MACRO_PLACEMENT_REPORT" || true)
  test "$placed_count" = "$NPC_ASIC_EXPECTED_MACRO_COUNT" || {
    echo "Macro placement count mismatch: $placed_count != $NPC_ASIC_EXPECTED_MACRO_COUNT" >&2
    exit 2
  }
fi

input_hash=$(sha256sum "$NPC_ASIC_MAPPED_NETLIST" | awk '{print $1}')
import_hash=$(sha256sum "$results_dir/1_2_yosys.v" | awk '{print $1}')
test "$input_hash" = "$import_hash" || {
  echo "FAIL_HANDOFF_IDENTITY: DC netlist differs from ORFS 1_2_yosys.v" >&2
  exit 2
}

cp "$results_dir/6_final.v" "$handoff/${NPC_ASIC_TOP}_postroute.v"
cp "$results_dir/6_final.spef" "$handoff/${NPC_ASIC_TOP}_postroute.spef"
cp "$results_dir/6_final.odb" "$handoff/${NPC_ASIC_TOP}_postroute.odb"
cp "$results_dir/6_final.def" "$handoff/${NPC_ASIC_TOP}_postroute.def"
python3 "$NPC_ASIC_ROOT/flows/scripts/sanitize_openroad_sdc.py" \
  --input "$results_dir/6_final.sdc" \
  --output "$handoff/${NPC_ASIC_TOP}_postroute.sdc" \
  --expected-period-ns "$NPC_ASIC_PNR_PERIOD_NS"
cp "$results_dir/6_final.gds" "$handoff/${NPC_ASIC_TOP}.gds"

(
  cd "$handoff"
  sha256sum "${NPC_ASIC_TOP}_postroute.v" \
    "${NPC_ASIC_TOP}_postroute.sdc" \
    "${NPC_ASIC_TOP}_postroute.spef" \
    "${NPC_ASIC_TOP}_postroute.odb" \
    "${NPC_ASIC_TOP}_postroute.def" \
    "${NPC_ASIC_TOP}.gds" > SHA256SUMS
)

cat > "$NPC_ASIC_BUILD_ROOT/openroad_contract.txt" <<EOF
design_nickname=$NPC_ASIC_DESIGN_NICKNAME
top=$NPC_ASIC_TOP
platform=nangate45
memory_mode=$NPC_ASIC_MEMORY_MODE
expected_macro_count=$NPC_ASIC_EXPECTED_MACRO_COUNT
pnr_period_ns=$NPC_ASIC_PNR_PERIOD_NS
orfs_commit=$NPC_ASIC_ORFS_COMMIT
orfs_actual_commit=$orfs_actual_commit
orfs_commit_verification=$orfs_commit_verification
orfs_image_digest=$NPC_ASIC_ORFS_IMAGE_DIGEST
orfs_image=$NPC_ASIC_ORFS_IMAGE
mapped_netlist_sha256=$input_hash
orfs_import_netlist_sha256=$import_hash
EOF

echo "INFO: OpenROAD/OpenRCX $NPC_ASIC_MEMORY_MODE handoff completed"
