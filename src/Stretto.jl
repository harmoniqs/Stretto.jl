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
adequate for 1-2 qubit problems. When `Piccolissimo` is loaded, the
`StrettoPiccolissimoExt` extension overrides this to return `SplineIntegrator`, which
scales to 3+ qubit compilation without exhausting memory during evaluator construction.

Users who want a different integrator can either load Piccolissimo or override this
function directly.
"""
default_integrator(qtraj, N) = BilinearIntegrator(qtraj, N)

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
export default_integrator

end # module
