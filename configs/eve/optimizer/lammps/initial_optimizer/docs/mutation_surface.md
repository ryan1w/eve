# Mutation Surface

You may edit exactly these files and folders:

- `run_kk.sh`
- `run_kk_bond.sh`
- `in.make_interface_bonds`
- `in.make_interface_bonds_kk`
- `in.make_interface_bonds_kk_bond`
- `lammps/src/`

The data file `sine068_1shear.dat` is required input, not an optimization
surface. Generated outputs such as `bond3x_local_kk.dump`, `sine068_1_kk.pull`,
`before_shearx_kk.data`, `final_shear_smooth_kk.lammpstrj`, restart files, and
LAMMPS build products are evaluation artifacts, not source changes.

Prefer changes that are easy to attribute:

- input-script parameter probes for bond creation, bond breakage, interface bond
  coefficients, shear rate, thermo/dump cadence, group definitions, and region
  bounds;
- source-level fixes or instrumentation in LAMMPS only when the input-level
  route is insufficient;
- small, reversible edits with a clear expected effect on type-3 bond creation,
  type-3 bond breakage, and simulation stability.
