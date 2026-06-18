# LAMMPS InterfaceBond Guidance

The target project is `https://github.com/ryan1w/InterfaceBond`.

Editable code is limited to LAMMPS input/run scripts and `lammps/src`. Do not
edit generated binaries, dump files, restart files, pull logs, bonded data
outputs, or the clean input data file `sine068_1shear.dat`.

Important constraints:

- Do not add or commit `lammps/src/lmp_mpi`, `lammps/src/lmp_serial`,
  `lammps/build*`, or generated `.dump`, `.pull`, `.lammpstrj`, `.data`, or
  restart outputs.
- Keep `run_kk_bond.sh` runnable from the repository root unless you also update
  the evaluation command contract.
- Preserve `sine068_1_kk.pull` as the thermo log containing energy and force
  observables.
- Preserve `shear_bonded_kk_1.dump` with `vx`, `vy`, and `vz` columns so the
  evaluator can compute velocity statistics.
- Keep changes minimal, testable, and physically interpretable.
- The evaluation script must always produce `score.yaml`.
