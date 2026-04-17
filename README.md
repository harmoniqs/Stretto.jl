# Stretto.jl

<!--```@raw html-->
<div align="center">
  <table>
    <tr>
      <td align="center">
        <b>Documentation</b>
        <br>
        <a href="https://docs.harmoniqs.co/Stretto/stable/">
          <img src="https://img.shields.io/badge/docs-stable-blue.svg" alt="Stable"/>
        </a>
        <a href="https://docs.harmoniqs.co/Stretto/dev/">
          <img src="https://img.shields.io/badge/docs-dev-blue.svg" alt="Dev"/>
        </a>
      </td>
      <td align="center">
        <b>Build Status</b>
        <br>
        <a href="https://github.com/harmoniqs/Stretto.jl/actions/workflows/CI.yml?query=branch%3Amain">
          <img src="https://github.com/harmoniqs/Stretto.jl/actions/workflows/CI.yml/badge.svg?branch=main" alt="Build Status"/>
        </a>
        <a href="https://codecov.io/gh/harmoniqs/Stretto.jl">
          <img src="https://codecov.io/gh/harmoniqs/Stretto.jl/branch/main/graph/badge.svg" alt="Coverage"/>
        </a>
      </td>
      <td align="center">
        <b>License</b>
        <br>
        <a href="https://opensource.org/licenses/MIT">
          <img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="MIT License"/>
        </a>
      </td>
    </tr>
  </table>
</div>
<!--```-->

**Stretto.jl** is the circuit-to-pulse compilation layer of the [Piccolo.jl](https://github.com/harmoniqs/Piccolo.jl) ecosystem. Given a gate-level circuit and a hardware device profile, Stretto synthesizes a single optimized control pulse that implements the whole circuit — skipping the intermediate gate decomposition and scheduling steps of a conventional compiler.

## What problem does it solve?

A conventional quantum compiler takes a high-level circuit, decomposes it into native gates, schedules them, and lowers each gate to a precomputed pulse. That pipeline leaves pulse-level fidelity on the table: every gate boundary is a re-initialization, every idle qubit is accumulating noise, every decomposition hides joint optimization opportunities.

Stretto treats the circuit as the target and asks Piccolo to solve for *one pulse* on the device that realizes the whole unitary. Concretely, for a circuit $U_\text{circ}$ and a device system $H_\text{sys}$:

```math
\begin{aligned}
\min_{u(t),\, \varphi} \quad & 1 - \mathcal{F}\!\left(U_\text{circ},\, V_\varphi \, U(T;\, u)\right) \\
\text{subject to}\quad & \dot{U}(t) = -i\,H_\text{sys}(u(t))\,U(t),\quad U(0) = I, \\
 & u_\text{min} \le u(t) \le u_\text{max},
\end{aligned}
```

where $V_\varphi$ are per-qubit virtual-Z phases (free-phase), $U(T;\,u)$ is the propagator at the pulse endpoint, and $\mathcal{F}$ is the Pedersen subspace fidelity on the device's computational levels.

## Installation

Stretto.jl is not yet registered. Install with:

```julia
using Pkg
Pkg.add(url="https://github.com/harmoniqs/Stretto.jl")
```

## Quick Example

```julia
using Stretto

# A 4-qubit IBM Heron r3 device profile
device = HeronR3()

# A circuit — Toffoli on qubits 1..3
circuit = toffoli_circuit()

# Compile to a pulse
report = compile(circuit, device; max_iter=100)

println(report)
# =>
# Stretto Compilation Report
# Circuit: 3Q circuit (1 gates) (3Q)  │  Target: ibm_heron_r3
# ──────────────────────────────────────────────────────────
#                   Gate-Level     Pulse-Level    Improvement
# Duration            410.0 ns        ... ns         ...×
# Fidelity           ...%            ...%           ...× error
```

## Key Features (v0.1)

- **Device profiles.** `HeronR3` (IBM Heron r3 model) plus the infrastructure to add others (`TransmonDevice` is a thin wrapper around Piccolo's `MultiTransmonSystem`).
- **Circuit IR.** `GateCircuit`, `GateOp`, `circuit_unitary` — plus built-in `qft_circuit(n)`, `toffoli_circuit()`, `ccz_circuit()`.
- **Single-pulse compilation.** `compile_block` wires a circuit + device subset → Piccolo `UnitaryTrajectory` → `SplinePulseProblem` → optimized pulse. `compile` does the whole circuit.
- **Gate-vs-pulse benchmarks.** `CompilationReport` compares the published gate-level baseline to the pulse-level result.
- **Integrator-agnostic.** Uses [Piccolissimo.jl](https://github.com/harmoniqs/Piccolissimo.jl)'s `SplineIntegrator` by default (fast on multi-qubit problems); integrator is a `kwarg`.

## Not yet in v0.1 (future work)

| Feature | Target |
|---|---|
| QASM import | v0.2 |
| Catalog warm-starts | v0.2 |
| Circuit partitioning | v0.3 |
| QEC kernel integration | v0.3 |
| Framework adapters (Qiskit/Cirq via PythonCall) | v0.4 |

## Contributing

### Running tests

Default suite (fast, no Piccolo solve):

```bash
julia --project=. test/runtests.jl
```

Integration suite (includes 2Q and 3Q compile smoke tests):

```bash
julia --project=. -e '
  using TestItemRunner
  TestItemRunner.run_tests("."; filter = ti -> :integration in ti.tags)
'
```

### Building Documentation

This package uses a Documenter config shared across the Harmoniqs monorepo. First-time setup:

```bash
./docs/get_docs_utils.sh
```

Build:

```bash
julia --project=docs docs/make.jl
```

Live editing:

```bash
julia --project=docs -e '
  using LiveServer, Stretto, Revise
  servedocs(
    literate_dir="docs/literate",
    skip_dirs=["docs/src/generated", "docs/src/assets/"],
    skip_files=["docs/src/index.md"]
  )'
```

> **Note:** `servedocs` will loop if it watches generated files. Keep generated files in the skip dirs/files args.

-----

*"Some people stretto; some people wait."*
