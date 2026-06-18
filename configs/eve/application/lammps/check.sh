#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${EVE_OUTPUT_ROOT:-}" ]]; then
  repo_root="$(cd "${EVE_OUTPUT_ROOT}" && pwd)"
  workspace_root="${EVE_WORKSPACE_ROOT:-$(cd "${repo_root}/.." && pwd)}"
elif [[ -n "${EVE_WORKSPACE_ROOT:-}" ]]; then
  workspace_root="$(cd "${EVE_WORKSPACE_ROOT}" && pwd)"
  repo_root="$(cd "${workspace_root}/output" && pwd)"
else
  repo_root="$(cd "${script_dir}/../../../.." && pwd)"
  workspace_root="$(cd "${repo_root}/.." && pwd)"
fi
check_log_root="${EVE_CHECK_LOG_ROOT:-${workspace_root}/logs/check-runner}"
mkdir -p "${check_log_root}"

fail_code() {
  local stage="$1"
  shift
  printf '[CHECK-CODE] stage=%s %s\n' "${stage}" "$*" >&2
  exit 1
}

fail_infra() {
  local stage="$1"
  shift
  printf '[CHECK-INFRA] stage=%s %s\n' "${stage}" "$*" >&2
  exit 1
}

if [[ -z "${EVE_BOUNDARY_CHECK_COMMAND:-}" ]]; then
  fail_infra "boundary_env_missing" "EVE_BOUNDARY_CHECK_COMMAND was empty"
fi
if ! bash -lc "${EVE_BOUNDARY_CHECK_COMMAND}" >"${check_log_root}/boundary_stdout.log" 2>"${check_log_root}/boundary_stderr.log"; then
  fail_code "boundary" "candidate changed files outside the allowed LAMMPS editable surface"
fi

required_paths=(
  "run_kk.sh"
  "run_kk_bond.sh"
  "in.make_interface_bonds"
  "in.make_interface_bonds_kk"
  "in.make_interface_bonds_kk_bond"
  "sine068_1shear.dat"
  "lammps/src"
  "lammps/cmake/CMakeLists.txt"
)
for rel in "${required_paths[@]}"; do
  if [[ ! -e "${repo_root}/${rel}" ]]; then
    fail_code "editable_surface" "missing required path ${rel}"
  fi
done

for script in run_kk.sh run_kk_bond.sh; do
  if ! bash -n "${repo_root}/${script}"; then
    fail_code "shell_syntax" "${script} has invalid shell syntax"
  fi
done

for input in in.make_interface_bonds in.make_interface_bonds_kk in.make_interface_bonds_kk_bond; do
  if ! grep -Eq '^[[:space:]]*(run|read_data|pair_style|bond_style)' "${repo_root}/${input}"; then
    fail_code "lammps_input" "${input} no longer looks like a LAMMPS input script"
  fi
done

if [[ "${EVE_LAMMPS_CHECK_BUILD:-0}" == "1" ]]; then
  build_log="${check_log_root}/build.log"
  build_command="${EVE_LAMMPS_BUILD_COMMAND:-cmake -S lammps/cmake -B lammps/build_kk -D BUILD_MPI=ON -D BUILD_OMP=ON -D CMAKE_BUILD_TYPE=Release -D CMAKE_CXX_COMPILER=${repo_root}/lammps/lib/kokkos/bin/nvcc_wrapper -D PKG_CLASS2=yes -D PKG_EXTRA-MOLECULE=yes -D PKG_KOKKOS=ON -D PKG_KSPACE=ON -D PKG_MANYBODY=yes -D PKG_MC=yes -D PKG_MOLECULE=yes -D PKG_RIGID=ON -D Kokkos_ENABLE_CUDA=ON -D Kokkos_ENABLE_CUDA_LAMBDA=ON -D Kokkos_ENABLE_OPENMP=ON -D Kokkos_ENABLE_SERIAL=ON -D Kokkos_ARCH_ADA89=yes -D FFT_KOKKOS=CUFFT && cmake --build lammps/build_kk -j $(nproc)}"
  if ! bash -lc "cd $(printf '%q' "${repo_root}") && ${build_command}" >"${build_log}" 2>&1; then
    fail_code "build" "LAMMPS build failed; see ${build_log}"
  fi
fi

printf '[CHECK-PASS] repo=%s check_log_root=%s\n' "${repo_root}" "${check_log_root}"
