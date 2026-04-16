module Stretto

using LinearAlgebra
using Printf
using TOML
using TestItems

using Piccolo
using Piccolo:
    # Systems
    QuantumSystem, MultiTransmonSystem, CompositeQuantumSystem,
    # Operators
    EmbeddedOperator, GATES, get_subspace_indices,
    # Pulses
    AbstractPulse, CubicSplinePulse, duration, n_drives,
    # Trajectories
    UnitaryTrajectory,
    # Problems
    SplinePulseProblem, PiccoloOptions,
    # Solving
    solve!, fidelity, get_trajectory, extract_pulse

include("devices.jl")
include("profiles.jl")
include("circuits.jl")
include("library.jl")
include("compile.jl")
include("report.jl")

export AbstractDevice, TransmonDevice, TransmonQubit, CouplingEdge
export HeronR3
export AbstractCircuit, GateOp, GateCircuit, circuit_unitary
export qft_circuit
export compile, compile_block
export CompilationReport, gate_level_baseline

end # module
