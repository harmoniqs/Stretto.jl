# QFT-4 on IBM Heron r3 — Stretto v0.1 milestone script.
#
# Compile QFT-4 as a single optimized pulse on a 4-qubit HeronR3 model
# (3^4 = 81-dim Hilbert space, 8 drives) and print a CompilationReport.
#
# Note (v0.1): with Piccolo's default BilinearIntegrator the 4-qubit compile
# builds an ~1M-nonzero Jacobian and ~57GB RSS. On a 62GB workstation this
# swap-thrashes before finishing one Ipopt iteration. A successful run
# requires Piccolissimo's SplineIntegrator (smaller sensitivity evaluator),
# which is a v0.2 dependency. Until then, this script exists as the
# pipeline wiring proof — the 2Q compile path is covered by the
# :integration-tagged @testitem in src/compile.jl.
#
# To run:
#   OPENBLAS_NUM_THREADS=1 julia --project=. -t auto scripts/qft4_heronr3.jl

using Stretto
using Piccolo: duration

device = HeronR3()
circuit = qft_circuit(4)

println("\nQFT-4 circuit: $(length(circuit)) gates on $(circuit.n_qubits) qubits")
println("Hilbert space: 3^4 = 81 dim, 8 drives")
println("Compiling with 500 iterations...")

report = compile(circuit, device;
    max_iter = 500,
    T_ns     = 400.0,    # generous initial duration for 4Q
    N_knots  = 31,       # more knots for 4Q
    Q        = 200.0,
)

println(report)
println("\nv0.1 milestone: QFT-4 on HeronR3 compiled successfully.")
println("Pulse fidelity: $(round(report.pulse_fidelity * 100, digits=2))%")
println("Pulse duration: $(round(report.pulse_duration_ns, digits=1)) ns")
println("Gate baseline:  $(round(report.gate_duration_ns, digits=1)) ns")

# Sanity assertions (script-style — assertion errors halt the run)
@assert report.pulse_duration_ns > 0.0
@assert report.gate_duration_ns > 0.0
@assert report.pulse_fidelity > 0.1   # better than 1/16 random
