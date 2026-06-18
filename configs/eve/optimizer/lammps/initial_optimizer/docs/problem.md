# LAMMPS InterfaceBond Problem

The target project is `https://github.com/ryan1w/InterfaceBond` at commit
`c82b4bf4b49bb0b6c7b483b257dc3c52be9d5a15`.

The simulation computes molecular energy, force/stress-style quantities, and
velocity fields during a bond-create/bond-break shear run. The current runnable
entrypoint is `run_kk_bond.sh`, which executes `in.make_interface_bonds_kk_bond`
with the Kokkos LAMMPS binary.

The default EvE evaluator is intentionally neutral: it parses observables and
checks stability, but uses `score_metric: stable_observables` and `score: 0.0`.
This avoids pretending that energy, force, or velocity should be maximized or
minimized without a physical target from the user.

Parsed observables include:

- final and initial thermo rows from `sine068_1_kk.pull`
- energy values such as `KinEng`, `PotEng` when present, and `TotEng`
- force/stress-style columns such as `v_Fy_int`, `v_Fx`, `v_Fypc`, `Press`,
  `Pyz`, `Pzz`, and `Pyy`
- final-frame velocity statistics from `shear_bonded_kk_1.dump`

If a real optimization target is desired, set `EVE_LAMMPS_OBJECTIVE` in the
evaluation environment. Supported first-pass scalar objectives are:

- `stable_observables` default neutral score
- `minimize_final_total_energy`
- `maximize_final_total_energy`
- `minimize_abs_total_energy_drift`
- `maximize_abs_interface_force_y`
- `minimize_rms_speed`

Do not optimize by faking output files, bypassing the simulation, deleting logs,
or making the system numerically unstable.
