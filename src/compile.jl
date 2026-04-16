"""
Result of compiling a single circuit block to a pulse.
"""
struct BlockResult
    pulse::AbstractPulse
    fidelity::Float64
    n_qubits::Int
end

"""
    compile_block(circuit, device, qubit_indices; max_iter, T_ns, N_knots, Q, free_phase)

Compile a circuit block to a single optimized pulse on a device qubit subset.

1. Build QuantumSystem from device
2. Compute target unitary → EmbeddedOperator (multi-level)
3. Cold-start CubicSplinePulse
4. UnitaryTrajectory → SplinePulseProblem → solve!
5. Extract optimized pulse
"""
function compile_block(
    circuit::AbstractCircuit,
    device::TransmonDevice,
    qubit_indices::AbstractVector{Int};
    max_iter::Int = 500,
    T_ns::Float64 = 200.0,
    N_knots::Int = 21,
    Q::Float64 = 100.0,
    free_phase::Bool = true,
)
    # 1. Build system
    sys = Piccolo.QuantumSystem(device, qubit_indices)
    n = length(qubit_indices)
    levels = subsystem_levels(device, qubit_indices)

    # 2. Target unitary (qubit-level) → embedded in multi-level space
    U_target = circuit_unitary(circuit)
    subspaces = [collect(1:2) for _ in 1:n]
    subspace = get_subspace_indices(subspaces, levels)
    U_goal = EmbeddedOperator(U_target, subspace, levels)

    # 3. Cold-start pulse (random, zero at boundaries)
    n_drv = sys.n_drives
    times = collect(range(0.0, T_ns, length=N_knots))
    u_init = 0.02 * randn(n_drv, N_knots)
    u_init[:, 1] .= 0.0
    u_init[:, end] .= 0.0
    du_init = zeros(n_drv, N_knots)
    pulse = CubicSplinePulse(u_init, du_init, times)

    # 4. Trajectory → Problem → Solve
    qtraj = UnitaryTrajectory(sys, pulse, U_goal)
    qcp = SplinePulseProblem(qtraj;
        Q = Q,
        free_phase = free_phase,
        subsystem_levels = levels,
    )
    solve!(qcp; max_iter=max_iter)

    # 5. Extract result
    traj = get_trajectory(qcp)
    result_pulse = extract_pulse(qtraj, traj)
    fid = fidelity(qcp)

    return BlockResult(result_pulse, fid, n)
end

"""
    compile(circuit, device; max_iter, kwargs...)

Compile an entire circuit on a device. v0.1: no partitioning — compiles
the whole circuit as a single block on qubits 1:n_qubits.
"""
function compile(circuit::AbstractCircuit, device::AbstractDevice; max_iter::Int=500, kwargs...)
    qubit_indices = collect(1:circuit.n_qubits)
    block = compile_block(circuit, device, qubit_indices; max_iter, kwargs...)
    baseline = gate_level_baseline(circuit, device)
    return CompilationReport(circuit, device, block, baseline)
end

# ============================================================================ #
# Tests
# ============================================================================ #
# Stretto v0.1 has no Piccolissimo dependency, so compile tests use Piccolo's
# default BilinearIntegrator — slow on anything bigger than 2 qubits.
# Integration tests are tagged `:integration` so they are opt-in, not part of
# the default `@run_package_tests` filter.

@testitem "compile_block — 2-qubit H→CZ (API smoke)" tags=[:integration] begin
    using Piccolo: AbstractPulse, duration
    device = HeronR3()
    circuit = GateCircuit(
        [GateOp(:H, (1,)), GateOp(:CZ, (1, 2))],
        2
    )

    result = compile_block(circuit, device, [1, 2]; max_iter=2)

    @test result.pulse isa AbstractPulse
    @test duration(result.pulse) > 0.0
    @test result.n_qubits == 2
    @test 0.0 ≤ result.fidelity ≤ 1.0
end
