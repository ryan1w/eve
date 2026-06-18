#!/usr/bin/env bash

set -euo pipefail

workspace_root="${EVE_WORKSPACE_ROOT:-$PWD}"
output_root="${EVE_OUTPUT_ROOT:-${workspace_root}/output}"
eval_log_root="${EVE_EVAL_LOG_ROOT:-${workspace_root}/logs/evaluate}"

mkdir -p "${eval_log_root}"

score_yaml="${eval_log_root}/score.yaml"
summary_json="${eval_log_root}/eval_summary.json"
error_txt="${eval_log_root}/error.txt"
build_stdout="${eval_log_root}/build_stdout.log"
build_stderr="${eval_log_root}/build_stderr.log"
run_stdout="${eval_log_root}/run_stdout.log"
run_stderr="${eval_log_root}/run_stderr.log"

failure_score="${FAILURE_SCORE:--10.0}"
lammps_binary="${EVE_LAMMPS_BINARY:-${output_root}/lammps/build_kk/lmp}"
thermo_log="${EVE_LAMMPS_THERMO_LOG:-sine068_1_kk.pull}"
velocity_dump="${EVE_LAMMPS_VELOCITY_DUMP:-shear_bonded_kk_1.dump}"
run_command="${EVE_LAMMPS_RUN_COMMAND:-bash ./run_kk_bond.sh}"
timeout_seconds="${EVE_LAMMPS_TIMEOUT_SECONDS:-1200}"
max_final_temp="${EVE_LAMMPS_MAX_FINAL_TEMP:-5000}"
objective="${EVE_LAMMPS_OBJECTIVE:-stable_observables}"

write_payload() {
  local payload_json="$1"
  python3 - "${score_yaml}" "${summary_json}" "${payload_json}" <<'PY_SCORE'
import json
import sys
from pathlib import Path

score_path = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
payload = json.loads(sys.argv[3])
score_path.write_text(json.dumps(payload, indent=2, sort_keys=False) + "\n", encoding="utf-8")
summary_path.write_text(json.dumps(payload, indent=2, sort_keys=False) + "\n", encoding="utf-8")
PY_SCORE
}

write_failure() {
  local reason="$1"
  local payload_json
  payload_json="$(python3 - "${failure_score}" "${reason}" <<'PY_FAIL'
import json
import sys
print(json.dumps({
    "score": float(sys.argv[1]),
    "summary": "evaluation failed",
    "score_metric": "candidate_failure",
    "score_components": {"reason": sys.argv[2]},
}))
PY_FAIL
)"
  write_payload "${payload_json}"
  printf '%s\n' "${reason}" >"${error_txt}"
}

require_path() {
  local rel="$1"
  if [[ ! -e "${output_root}/${rel}" ]]; then
    write_failure "missing required candidate path: ${rel}"
    exit 0
  fi
}

build_lammps_if_needed() {
  if [[ "${EVE_LAMMPS_SKIP_BUILD:-0}" == "1" ]]; then
    return 0
  fi
  if [[ -x "${lammps_binary}" && "${EVE_LAMMPS_FORCE_REBUILD:-0}" != "1" ]]; then
    return 0
  fi

  local build_command
  build_command="${EVE_LAMMPS_BUILD_COMMAND:-cmake -S lammps/cmake -B lammps/build_kk -D BUILD_MPI=ON -D BUILD_OMP=ON -D CMAKE_BUILD_TYPE=Release -D CMAKE_CXX_COMPILER=${output_root}/lammps/lib/kokkos/bin/nvcc_wrapper -D PKG_CLASS2=yes -D PKG_EXTRA-MOLECULE=yes -D PKG_KOKKOS=ON -D PKG_KSPACE=ON -D PKG_MANYBODY=yes -D PKG_MC=yes -D PKG_MOLECULE=yes -D PKG_RIGID=ON -D Kokkos_ENABLE_CUDA=ON -D Kokkos_ENABLE_CUDA_LAMBDA=ON -D Kokkos_ENABLE_OPENMP=ON -D Kokkos_ENABLE_SERIAL=ON -D Kokkos_ARCH_ADA89=yes -D FFT_KOKKOS=CUFFT && cmake --build lammps/build_kk -j $(nproc)}"

  if ! bash -lc "cd $(printf '%q' "${output_root}") && ${build_command}" >"${build_stdout}" 2>"${build_stderr}"; then
    write_failure "LAMMPS build failed; see build_stdout.log and build_stderr.log"
    exit 0
  fi
  if [[ ! -x "${lammps_binary}" ]]; then
    write_failure "LAMMPS build completed but binary is missing or not executable: ${lammps_binary}"
    exit 0
  fi
}

run_lammps() {
  rm -f \
    "${output_root}/${thermo_log}" \
    "${output_root}/${velocity_dump}" \
    "${output_root}/bond3x_local_kk.dump" \
    "${output_root}/before_shearx_kk.data" \
    "${output_root}/final_shear_smooth_kk.lammpstrj" \
    "${output_root}/sigmatex22shear_bonded_kk.data"

  local wrapped_command
  if command -v timeout >/dev/null 2>&1; then
    wrapped_command="timeout ${timeout_seconds}s ${run_command}"
  else
    wrapped_command="${run_command}"
  fi

  if ! bash -lc "cd $(printf '%q' "${output_root}") && ${wrapped_command}" >"${run_stdout}" 2>"${run_stderr}"; then
    write_failure "LAMMPS run failed or timed out; see run_stdout.log and run_stderr.log"
    exit 0
  fi
}

parse_outputs() {
  python3 - \
    "${output_root}" \
    "${eval_log_root}" \
    "${thermo_log}" \
    "${velocity_dump}" \
    "${max_final_temp}" \
    "${objective}" <<'PY_PARSE'
import json
import math
import os
import re
import sys
from pathlib import Path

output_root = Path(sys.argv[1])
eval_log_root = Path(sys.argv[2])
thermo_log_name = sys.argv[3]
velocity_dump_name = sys.argv[4]
max_final_temp = float(sys.argv[5])
objective = sys.argv[6]

thermo_log = output_root / thermo_log_name
velocity_dump = output_root / velocity_dump_name
score_yaml = eval_log_root / "score.yaml"
summary_json = eval_log_root / "eval_summary.json"
error_txt = eval_log_root / "error.txt"


def write_payload(payload: dict[str, object]) -> None:
    score_yaml.write_text(json.dumps(payload, indent=2, sort_keys=False) + "\n", encoding="utf-8")
    summary_json.write_text(json.dumps(payload, indent=2, sort_keys=False) + "\n", encoding="utf-8")


def fail(reason: str) -> None:
    payload = {
        "score": -10.0,
        "summary": "evaluation failed",
        "score_metric": "candidate_failure",
        "score_components": {"reason": reason},
    }
    write_payload(payload)
    error_txt.write_text(reason + "\n", encoding="utf-8")


def assert_finite(value: object, label: str) -> None:
    if not isinstance(value, (int, float)) or not math.isfinite(float(value)):
        fail(f"non-finite or missing numeric value for {label}: {value!r}")
        raise SystemExit(0)


def parse_thermo(path: Path) -> tuple[list[str], list[dict[str, float]]]:
    if not path.is_file():
        fail(f"missing thermo log: {path.name}")
        raise SystemExit(0)
    header: list[str] | None = None
    final_header: list[str] = []
    rows: list[dict[str, float]] = []
    number_re = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$")
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = raw.split()
        if not parts:
            continue
        if parts[0] == "Step":
            header = parts
            final_header = parts
            continue
        if header and len(parts) == len(header) and all(number_re.match(part) for part in parts):
            rows.append({key: float(value) for key, value in zip(header, parts, strict=False)})
    if not rows:
        fail(f"no thermo rows found in {path.name}")
        raise SystemExit(0)
    return final_header, rows


def parse_velocity_dump(path: Path) -> dict[str, float | int | None]:
    if not path.is_file():
        fail(f"missing velocity dump: {path.name}")
        raise SystemExit(0)
    last_stats: dict[str, float | int | None] | None = None
    with path.open(encoding="utf-8", errors="replace") as handle:
        while True:
            line = handle.readline()
            if not line:
                break
            if not line.startswith("ITEM: TIMESTEP"):
                continue
            try:
                timestep = int(float(handle.readline().strip()))
            except ValueError:
                fail(f"failed to parse timestep in {path.name}")
                raise SystemExit(0)
            marker = handle.readline()
            if not marker.startswith("ITEM: NUMBER OF ATOMS"):
                fail(f"unexpected velocity dump marker after timestep {timestep}: {marker.strip()!r}")
                raise SystemExit(0)
            try:
                atoms = int(float(handle.readline().strip()))
            except ValueError:
                fail(f"failed to parse atom count after timestep {timestep}")
                raise SystemExit(0)
            box_marker = handle.readline()
            if not box_marker.startswith("ITEM: BOX BOUNDS"):
                fail(f"unexpected box marker after timestep {timestep}: {box_marker.strip()!r}")
                raise SystemExit(0)
            for _ in range(3):
                handle.readline()
            atom_marker = handle.readline().split()
            if len(atom_marker) < 3 or atom_marker[:2] != ["ITEM:", "ATOMS"]:
                fail(f"unexpected atom marker after timestep {timestep}: {' '.join(atom_marker)!r}")
                raise SystemExit(0)
            columns = atom_marker[2:]
            index = {name: idx for idx, name in enumerate(columns)}
            if not {"vx", "vy", "vz"}.issubset(index):
                fail(f"velocity dump {path.name} does not contain vx/vy/vz columns")
                raise SystemExit(0)
            count = 0
            sum_vx = sum_vy = sum_vz = sum_speed2 = max_speed = 0.0
            for _ in range(atoms):
                parts = handle.readline().split()
                try:
                    vx = float(parts[index["vx"]])
                    vy = float(parts[index["vy"]])
                    vz = float(parts[index["vz"]])
                except (IndexError, ValueError):
                    continue
                speed2 = vx * vx + vy * vy + vz * vz
                sum_vx += vx
                sum_vy += vy
                sum_vz += vz
                sum_speed2 += speed2
                max_speed = max(max_speed, math.sqrt(speed2))
                count += 1
            if count == 0:
                fail(f"no parseable velocity rows found at timestep {timestep} in {path.name}")
                raise SystemExit(0)
            last_stats = {
                "timestep": timestep,
                "atoms": atoms,
                "parsed_atoms": count,
                "mean_vx": sum_vx / count,
                "mean_vy": sum_vy / count,
                "mean_vz": sum_vz / count,
                "rms_speed": math.sqrt(sum_speed2 / count),
                "max_speed": max_speed,
            }
    if last_stats is None:
        fail(f"no frames found in velocity dump: {path.name}")
        raise SystemExit(0)
    return last_stats

thermo_columns, thermo_rows = parse_thermo(thermo_log)
first_thermo = thermo_rows[0]
final_thermo = thermo_rows[-1]
velocity = parse_velocity_dump(velocity_dump)

for key in ("Step", "KinEng", "TotEng"):
    assert_finite(final_thermo.get(key), f"final thermo {key}")
for key in ("rms_speed", "max_speed", "mean_vx", "mean_vy", "mean_vz"):
    assert_finite(velocity.get(key), f"velocity {key}")

final_temp = final_thermo.get("Temp")
if isinstance(final_temp, (int, float)):
    if not math.isfinite(float(final_temp)) or float(final_temp) > max_final_temp:
        fail(f"unstable final temperature: {final_temp}")
        raise SystemExit(0)

energy = {
    "initial_total_energy": first_thermo.get("TotEng"),
    "final_total_energy": final_thermo.get("TotEng"),
    "final_kinetic_energy": final_thermo.get("KinEng"),
    "final_potential_energy": final_thermo.get("PotEng"),
}
if isinstance(energy["initial_total_energy"], (int, float)) and isinstance(energy["final_total_energy"], (int, float)):
    energy["total_energy_drift"] = float(energy["final_total_energy"]) - float(energy["initial_total_energy"])
    denom = max(abs(float(energy["initial_total_energy"])), 1.0)
    energy["relative_total_energy_drift"] = float(energy["total_energy_drift"]) / denom
else:
    energy["total_energy_drift"] = None
    energy["relative_total_energy_drift"] = None

force = {key: value for key, value in final_thermo.items() if key.startswith("v_F")}
force.update({key: final_thermo[key] for key in ("Press", "Pyz", "Pzz", "Pyy") if key in final_thermo})

score_metric = objective
if objective == "stable_observables":
    score = 0.0
elif objective == "minimize_final_total_energy":
    score = -float(final_thermo["TotEng"])
elif objective == "maximize_final_total_energy":
    score = float(final_thermo["TotEng"])
elif objective == "minimize_abs_total_energy_drift":
    drift = energy.get("total_energy_drift")
    if not isinstance(drift, (int, float)):
        fail("cannot compute total energy drift for requested objective")
        raise SystemExit(0)
    score = -abs(float(drift))
elif objective == "maximize_abs_interface_force_y":
    value = force.get("v_Fy_int") or force.get("v_Fypc")
    if not isinstance(value, (int, float)):
        fail("cannot find v_Fy_int or v_Fypc for requested force objective")
        raise SystemExit(0)
    score = abs(float(value))
elif objective == "minimize_rms_speed":
    score = -float(velocity["rms_speed"])
else:
    fail(
        "unknown EVE_LAMMPS_OBJECTIVE "
        f"{objective!r}; expected stable_observables, minimize_final_total_energy, "
        "maximize_final_total_energy, minimize_abs_total_energy_drift, "
        "maximize_abs_interface_force_y, or minimize_rms_speed"
    )
    raise SystemExit(0)

score_components = {
    "score_metric": score_metric,
    "objective": objective,
    "thermo_columns": thermo_columns,
    "first_thermo": first_thermo,
    "final_thermo": final_thermo,
    "energy": energy,
    "force": force,
    "velocity": velocity,
}
payload = {
    "score": float(score),
    "summary": (
        f"{score_metric}; final_toteng={float(final_thermo['TotEng']):.6g}; "
        f"final_kineng={float(final_thermo['KinEng']):.6g}; "
        f"rms_speed={float(velocity['rms_speed']):.6g}"
    ),
    "score_metric": score_metric,
    "score_components": score_components,
}
write_payload(payload)
if error_txt.exists():
    error_txt.unlink()
PY_PARSE
}

require_path "run_kk_bond.sh"
require_path "in.make_interface_bonds_kk_bond"
require_path "sine068_1shear.dat"
require_path "lammps/cmake/CMakeLists.txt"

build_lammps_if_needed
run_lammps
parse_outputs
