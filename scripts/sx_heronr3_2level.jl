# Single-qubit √X (SX) on a 2-level HeronR3 — public Stretto demo.
#
# Run from the package root:
#     OPENBLAS_NUM_THREADS=1 julia --project=. scripts/sx_heronr3_2level.jl
#
# Cold-start cubic-spline pulse, 60 ns total, 15 knots, free-phase = true.
# Reproducible (fixed RNG seed). Hits F ≥ 0.99 in ~90 s on a workstation.
#
# `n_levels = 2` truncates each transmon to its qubit subspace — fast (4-dim
# 2Q Hilbert space if you scale this up to a 2Q gate). Drop the kwarg or set
# n_levels = 3 to add the |2⟩ leakage level back in (slower, more realistic).

using Random
using Stretto

Random.seed!(0xc0ffee)

device = HeronR3(n_levels = 2)
circuit = GateCircuit([GateOp(:SX, (1,))], 1)

t0 = time()
report = compile(
    circuit,
    device;
    max_iter = 3000,
    T_ns = 60.0,
    N_knots = 15,
    Q = 100.0,
    free_phase = true,
)
t = time() - t0

println("\n=== Stretto Compilation Report ===")
println("Gate            : SX  (√X)")
println("Device          : ", device.name, "  (", device.qubits[1].n_levels, " levels)")
println("Pulse fidelity  : ", round(report.pulse_fidelity, digits = 5))
println("Pulse duration  : ", round(report.pulse_duration_ns, digits = 1), " ns")
println("Wall clock      : ", round(t, digits = 1), " s")
