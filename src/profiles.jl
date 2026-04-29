"""
    HeronR3()

IBM Heron r3 device profile. Parameters from published specs (2024-2026)
and Aumann et al. (arXiv:2604.12465).

Heavy-hex topology, CZ-native, 156 qubits. This profile models the first
8 qubits in a linear chain (sufficient for QFT-4 and QFT-8 benchmarks).
"""
function HeronR3()
    # Typical Heron r3 parameters (from published calibration data)
    # Frequencies staggered to avoid frequency collisions
    qubits = [
        TransmonQubit(5.00, 0.21, 3),
        TransmonQubit(4.85, 0.20, 3),
        TransmonQubit(5.05, 0.22, 3),
        TransmonQubit(4.90, 0.20, 3),
        TransmonQubit(5.10, 0.21, 3),
        TransmonQubit(4.80, 0.19, 3),
        TransmonQubit(5.03, 0.21, 3),
        TransmonQubit(4.95, 0.20, 3),
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
    )

    T1 = fill(68.0, 8)   # μs (mean from Willow spec)
    T2 = fill(35.0, 8)   # μs (estimated)

    return TransmonDevice("ibm_heron_r3", qubits, edges, native_gates, 0.05, T1, T2)
end
