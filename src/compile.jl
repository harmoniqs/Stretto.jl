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
    integrator = nothing,
)
    # 1. Build a composite Piccolo system directly (no flattening)
    sys = MultiTransmonSystem(device, qubit_indices)
    n = length(qubit_indices)

    # 2. Target unitary → embedded using the composite's own subsystem_levels
    U_target = circuit_unitary(circuit)
    U_goal = EmbeddedOperator(U_target, sys)

    # 3. Cold-start pulse (random, zero at boundaries)
    times = collect(range(0.0, T_ns, length=N_knots))
    u_init = 0.02 * randn(sys.n_drives, N_knots)
    u_init[:, 1] .= 0.0
    u_init[:, end] .= 0.0
    du_init = zeros(sys.n_drives, N_knots)
    pulse = CubicSplinePulse(u_init, du_init, times)

    # 4. Trajectory → Problem → Solve
    qtraj = UnitaryTrajectory(sys, pulse, U_goal)
    # Default integrator seam: Piccolo's BilinearIntegrator is adequate for
    # 1-2 qubit problems. The private Strettissimo package overrides this via
    # `set_default_integrator!` to install Piccolissimo's SplineIntegrator for
    # multi-qubit compilation. Caller can also pass `integrator=` directly.
    integ = integrator === nothing ? default_integrator(qtraj, N_knots) : integrator
    qcp = SplinePulseProblem(qtraj;
        integrator = integ,
        Q = Q,
        free_phase = free_phase,
        subsystem_levels = sys.subsystem_levels,
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
# Stretto's default test suite uses Piccolo's BilinearIntegrator. Multi-qubit
# integration tests live in the private Strettissimo package, which overrides
# `default_integrator` with Piccolissimo's SplineIntegrator.

@testitem "default_integrator — substrate returns BilinearIntegrator" begin
    using Stretto
    using Piccolo: BilinearIntegrator, UnitaryTrajectory, CubicSplinePulse, QuantumSystem

    σz = ComplexF64[1 0; 0 -1]
    σx = ComplexF64[0 1; 1 0]
    sys = QuantumSystem(σz, [σx], [1.0])
    times = collect(range(0.0, 10.0, length=5))
    pulse = CubicSplinePulse(zeros(1, 5), zeros(1, 5), times)
    qtraj = UnitaryTrajectory(sys, pulse, ComplexF64[1 0; 0 1])

    integ = Stretto.default_integrator(qtraj, 5)
    @test integ isa BilinearIntegrator
end

