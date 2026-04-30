"""
    HeronR3(; n_levels::Int = 3)

IBM Heron r3 device profile. Parameters from published specs (2024-2026)
and Aumann et al. (arXiv:2604.12465).

Heavy-hex topology, CZ-native, 156 qubits. This profile models the first
8 qubits in a linear chain (sufficient for QFT-4 and QFT-8 benchmarks).

# Keyword Arguments
- `n_levels::Int = 3`: number of levels per transmon. The default `3`
  models the second-excited (`|2⟩`) leakage level explicitly — physically
  accurate for closed-system optimization. Setting `n_levels = 2` truncates
  to the qubit subspace, giving a 4-dim 2Q Hilbert space (vs 9-dim for
  3-level). Use `n_levels = 2` for fast 1Q–2Q demos where leakage isn't
  the focus.
"""
function HeronR3(; n_levels::Int = 3)
    # Typical Heron r3 parameters (from published calibration data)
    # Frequencies staggered to avoid frequency collisions
    qubits = [
        TransmonQubit(5.00, 0.21, n_levels),
        TransmonQubit(4.85, 0.20, n_levels),
        TransmonQubit(5.05, 0.22, n_levels),
        TransmonQubit(4.90, 0.20, n_levels),
        TransmonQubit(5.10, 0.21, n_levels),
        TransmonQubit(4.80, 0.19, n_levels),
        TransmonQubit(5.03, 0.21, n_levels),
        TransmonQubit(4.95, 0.20, n_levels),
    ]

    # Heavy-hex nearest-neighbor coupling (linear chain subset)
    edges = [
        CouplingEdge(1, 2, 0.003),
        CouplingEdge(2, 3, 0.003),
        CouplingEdge(3, 4, 0.003),
        CouplingEdge(4, 5, 0.003),
        CouplingEdge(5, 6, 0.003),
        CouplingEdge(6, 7, 0.003),
        CouplingEdge(7, 8, 0.003),
    ]

    # Published gate performance (Willow/Heron class)
    native_gates = Dict{Symbol,GateSpec}(
        :CZ => GateSpec(60.0, 0.0033),    # 60 ns, 0.33% error
        :X => GateSpec(25.0, 0.00035),    # 25 ns, 0.035% error
        :SX => GateSpec(25.0, 0.00035),    # √X, same as X
        :H => GateSpec(35.0, 0.0005),     # synthesized via SX·RZ (virtual-Z); estimate
    )

    T1 = fill(68.0, 8)   # μs (mean from Willow spec)
    T2 = fill(35.0, 8)   # μs (estimated)

    return TransmonDevice("ibm_heron_r3", qubits, edges, native_gates, 0.05, T1, T2)
end
