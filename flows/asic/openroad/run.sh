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
: "${NPC_ASIC_ORFS_COMMIT:?Missing NPC_ASIC_ORFS_COMMIT}"

case "$NPC_ASIC_ORFS_IMAGE" in
  *@sha256:*) ;;
  *) echo "NPC_ASIC_ORFS_IMAGE must be pinned by repository digest" >&2; exit 2 ;;
esac

for path in "$NPC_ASIC_MAPPED_NETLIST" "$NPC_ASIC_PNR_SDC"; do
  test -s "$path" || { echo "Missing P&R input: $path" >&2; exit 2; }
done

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
netlist_real=$(realpath "$NPC_ASIC_MAPPED_NETLIST")
sdc_real=$(realpath "$NPC_ASIC_PNR_SDC")
for path in "$netlist_real" "$sdc_real"; do
  case "$path" in
    "$root_real"/*) ;;
    *) echo "Container input must be below NPC_ASIC_ROOT: $path" >&2; exit 2 ;;
  esac
done

uid=$(id -u)
gid=$(id -g)
results_dir="$work_home/results/nangate45/$NPC_ASIC_DESIGN_NICKNAME/base"

"$docker_tool" run --rm \
  -u "$uid:$gid" \
  -v "$root_real:/npc" \
  -e NPC_ASIC_DESIGN_NICKNAME="$NPC_ASIC_DESIGN_NICKNAME" \
  -e NPC_ASIC_TOP="$NPC_ASIC_TOP" \
  -e NPC_ASIC_MAPPED_NETLIST="/npc/${netlist_real#"$root_real"/}" \
  -e NPC_ASIC_PNR_SDC="/npc/${sdc_real#"$root_real"/}" \
  -e NPC_ASIC_DIE_AREA="$NPC_ASIC_DIE_AREA" \
  -e NPC_ASIC_CORE_AREA="$NPC_ASIC_CORE_AREA" \
  -e NPC_ASIC_PLACE_DENSITY="$NPC_ASIC_PLACE_DENSITY" \
  -w /OpenROAD-flow-scripts/flow \
  "$NPC_ASIC_ORFS_IMAGE" \
  bash -lc "source /OpenROAD-flow-scripts/env.sh && make DESIGN_CONFIG=/npc/flows/asic/openroad/config.mk WORK_HOME='$build_in_container/orfs'"

for artifact in 1_2_yosys.v 6_final.odb 6_final.def 6_final.v 6_final.sdc 6_final.spef 6_final.gds; do
  test -s "$results_dir/$artifact" || {
    echo "Missing ORFS final artifact: $results_dir/$artifact" >&2
    exit 2
  }
done

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
memory_mode=registers
macro_count=0
pnr_period_ns=$NPC_ASIC_PNR_PERIOD_NS
orfs_commit=$NPC_ASIC_ORFS_COMMIT
orfs_image=$NPC_ASIC_ORFS_IMAGE
mapped_netlist_sha256=$input_hash
orfs_import_netlist_sha256=$import_hash
EOF

echo "INFO: OpenROAD/OpenRCX register-expanded handoff completed"
