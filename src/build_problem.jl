"""
    PostProcessContext(circuit, device, qtraj, problem)

Carries the inter-stage state needed by `post_process` transforms.
Passed to each entry of a strategy's `post_process::Vector{Function}` list.
"""
struct PostProcessContext
    circuit::AbstractCircuit
    device::AbstractDevice
    qtraj::Any      # UnitaryTrajectory, but avoid tight type binding at compile-time
    problem::Any    # AbstractPiccoloProblem
end

"""
    build_problem(circuit, device, qtraj; kwargs...)

Construct the Piccolo problem to solve. Substrate: `SplinePulseProblem(qtraj; kwargs...)`
with all keyword arguments forwarded transparently. Strategies may override to
use `SmoothPulseProblem`, custom constraint sets, density-matrix trajectories,
or multi-objective formulations.

`kwargs` are forwarded to the underlying problem constructor (Q, free_phase,
integrator, subsystem_levels, etc.); callers pass them through from
`compile_block`.
"""
build_problem(circuit, device, qtraj; kwargs...) =
    _BUILD_PROBLEM[](circuit, device, qtraj; kwargs...)

function _substrate_build_problem(circuit, device, qtraj; kwargs...)
    return SplinePulseProblem(qtraj; kwargs...)
end

const _BUILD_PROBLEM = Ref{Any}(_substrate_build_problem)

"""
    set_build_problem!(f)

Install `f` as the problem builder. `f` must have signature
`(circuit, device, qtraj; kwargs...) -> AbstractPiccoloProblem`.
"""
set_build_problem!(f) = (_BUILD_PROBLEM[] = f)

@testitem "build_problem — substrate constructs SplinePulseProblem" begin
    using Stretto
    using Piccolo:
        UnitaryTrajectory,
        CubicSplinePulse,
        QuantumSystem,
        SplinePulseProblem,
        QuantumControlProblem

    σz = ComplexF64[1 0; 0 -1];
    σx = ComplexF64[0 1; 1 0]
    sys = QuantumSystem(σz, [σx], [1.0])
    times = collect(range(0.0, 10.0, length = 5))
    pulse = CubicSplinePulse(
        zeros(1, 5),
        zeros(1, 5),
        times;
        initial_value = zeros(1),
        final_value = zeros(1),
    )
    qtraj = UnitaryTrajectory(sys, pulse, ComplexF64[1 0; 0 1])

    device = HeronR3()
    circuit = GateCircuit([GateOp(:H, (1,))], 1)

    problem = Stretto.build_problem(circuit, device, qtraj)
    # Piccolo's concrete problem type returned by SplinePulseProblem.
    # (Piccolo does not export an `AbstractPiccoloProblem` supertype.)
    @test problem isa QuantumControlProblem
end
