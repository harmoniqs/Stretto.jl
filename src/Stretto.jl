module Stretto

using LinearAlgebra
using Printf
using TOML
using TestItems

using Piccolo
using Piccolo:
    # Systems
    AbstractQuantumSystem, QuantumSystem, MultiTransmonSystem, CompositeQuantumSystem,
    # Operators
    EmbeddedOperator, GATES, get_subspace_indices,
    # Pulses
    AbstractPulse, CubicSplinePulse, duration, n_drives,
    # Trajectories
    UnitaryTrajectory,
    # Integrators
    BilinearIntegrator,
    # Problems
    SplinePulseProblem, PiccoloOptions,
    # Solving
    solve!, fidelity, get_trajectory, extract_pulse

"""
    default_integrator(qtraj, N)

Return the integrator used by `compile_block`. Default: Piccolo's `BilinearIntegrator`,
adequate for 1-2 qubit problems. When the private `Strettissimo` package is
loaded, its `__init__` installs a `SplineIntegrator` builder via
[`set_default_integrator!`](@ref), which scales to 3+ qubit compilation without
exhausting memory during evaluator construction.

Users who want a different integrator can either load Strettissimo or call
`set_default_integrator!` with a custom builder `(qtraj, N) -> integrator`.
"""
default_integrator(qtraj, N) = _DEFAULT_INTEGRATOR[](qtraj, N)

# Mutable default builder — swapped by Strettissimo's `__init__` at load time.
# We indirect through a Ref-held builder function so downstream packages can
# install overrides without redefining methods on types they don't own.
const _DEFAULT_INTEGRATOR = Ref{Any}(
    (qtraj, N) -> BilinearIntegrator(qtraj, N)
)

"""
    set_default_integrator!(builder)

Install a new builder function for [`default_integrator`](@ref). `builder` must
accept `(qtraj, N)` and return an `AbstractIntegrator`. Intended primarily for
use by the private `Strettissimo` package, but callers can also use it to
plug in custom integrators without editing Stretto source.
"""
set_default_integrator!(builder) = (_DEFAULT_INTEGRATOR[] = builder; builder)

include("devices.jl")
include("profiles.jl")
include("circuits.jl")
include("library.jl")
include("compile.jl")
include("report.jl")

export AbstractDevice, TransmonDevice, TransmonQubit, CouplingEdge
export HeronR3
export AbstractCircuit, GateOp, GateCircuit, circuit_unitary
export qft_circuit, toffoli_circuit, ccz_circuit
export compile, compile_block
export CompilationReport, gate_level_baseline
export default_integrator, set_default_integrator!

end # module
