# Directions

This file is a map of plausible search families, not a ranked prescription.
Use it to diversify attempts when recent candidates cluster too tightly.

Because the default objective is neutral, changes should be framed as improving
or clarifying the energy/force/velocity simulation unless a scalar objective is
explicitly configured with `EVE_LAMMPS_OBJECTIVE`.

## 1. Observable quality

Improve the reliability, cadence, and clarity of thermo and dump outputs that
report energy, force/stress, and velocity. Preserve evaluator-facing files:
`sine068_1_kk.pull` and `shear_bonded_kk_1.dump`.

## 2. Energy behavior

Probe timestep, thermostat, bond coefficients, relaxation length, and constraints
that affect `KinEng`, `PotEng`, `TotEng`, and energy drift. Favor physically
interpretable energy behavior over purely numeric score chasing.

## 3. Force and stress response

Investigate interface force variables such as `v_Fy_int`, group force reductions,
and stress/pressure columns. Make force definitions clearer before optimizing a
force scalar.

## 4. Velocity field behavior

Inspect top-group motion, mobile/frozen group definitions, velocity initialization,
and integration choices that affect `vx`, `vy`, `vz`, RMS speed, and max speed.

## 5. Bond-create/bond-break mechanics

The simulation includes bond creation and breaking, but bond counts are not the
objective by default. Modify these settings only when they are relevant to the
energy/force/velocity behavior being studied.

## 6. Source-level LAMMPS changes

Only modify `lammps/src` when input-level changes cannot express the idea. Keep
source changes narrowly scoped to force, velocity, energy accounting, Kokkos
behavior, or diagnostics needed by the evaluator.

## Meta-rule

Score improvements only mean something after the scalar objective is physically
specified. Until then, prioritize stable, inspectable simulations and clear
observables over artificial scalar movement.
