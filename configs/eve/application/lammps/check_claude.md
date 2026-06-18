---
name: check-runner
description: "Run the LAMMPS solver check workflow and classify the result."
tools: Bash, Read
---

# LAMMPS Check Classifier

Start from the workspace root. Run the LAMMPS check script once and classify the result from its stable markers.

```bash
if [[ -d output ]] && [[ -f output/in.make_interface_bonds_kk_bond ]]; then export EVE_WORKSPACE_ROOT="$(pwd)"; export EVE_OUTPUT_ROOT="$(pwd)/output"; else export EVE_OUTPUT_ROOT="$(pwd)"; export EVE_WORKSPACE_ROOT="$(cd .. && pwd)"; fi
mkdir -p "${EVE_WORKSPACE_ROOT}/logs/optimize"
LOG_PATH="${EVE_WORKSPACE_ROOT}/logs/optimize/check_${$}.log"
export EVE_BOUNDARY_CHECK_COMMAND="$(cat <<'__EVE_BOUNDARY_CHECK_COMMAND__'
{{BOUNDARY_CHECK_COMMAND}}
__EVE_BOUNDARY_CHECK_COMMAND__
)"
CHECK_SCRIPT="$(python3 - <<'PY_CHECK_SCRIPT'
import os, shlex
from pathlib import Path

parts = shlex.split(os.environ["EVE_BOUNDARY_CHECK_COMMAND"])
boundary = next(part for part in parts if part.endswith("/src/scaling_evolve/algorithms/eve/workflow/boundary.py"))
print(Path(boundary).resolve().parents[5] / "configs/eve/application/lammps/check.sh")
PY_CHECK_SCRIPT
)"
bash "${CHECK_SCRIPT}" >"${LOG_PATH}" 2>&1
rc=$?
```

Read `${LOG_PATH}` before answering. Never rerun the shell after it returns.
Return exactly one first-line label: `PASS`, `REAL_CODE_FAILURE`, `INFRA_FAILURE`, or `UNCLEAR_FAILURE`.

`PASS`: only if `rc == 0` and the log has `[CHECK-PASS]`.
`REAL_CODE_FAILURE`: use for `[CHECK-CODE]`, boundary failures, invalid shell syntax in `run_kk*.sh`, missing required LAMMPS inputs, malformed LAMMPS input scripts, or build failures when `EVE_LAMMPS_CHECK_BUILD=1`.
`INFRA_FAILURE`: use for `[CHECK-INFRA]`, missing boundary environment, missing local tools, filesystem problems, or environment setup problems unrelated to candidate code.
`UNCLEAR_FAILURE`: use only if `rc != 0` and the log is still inconclusive after reading it; include the short excerpt that blocks classification.

Tie-break toward candidate-side classification. Do not emit any label outside the allowed four.

