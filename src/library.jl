"""
    qft_circuit(n::Int)

Build a QFT circuit on `n` qubits using H, controlled-phase, and SWAP gates.
Standard decomposition: for each qubit k (1..n), apply H then controlled-Rz
rotations from qubit k to all subsequent qubits, then swap to bit-reverse.
"""
function qft_circuit(n::Int)
    ops = GateOp[]

    # QFT core
    for k in 1:n
        push!(ops, GateOp(:H, (k,)))
        for j in (k+1):n
            # Controlled-phase: CP(π/2^(j-k)) on (k, j)
            # We represent this as a named parametric gate
            θ = π / 2^(j - k)
            gate_name = Symbol("CP_$(j-k)")
            # Register the gate if not already present
            if !haskey(EXTRA_GATES, gate_name)
                EXTRA_GATES[gate_name] = cp_gate(θ)
            end
            push!(ops, GateOp(gate_name, (k, j)))
        end
    end

    # Bit reversal via SWAPs
    # SWAP = CX(1,2) * CX(2,1) * CX(1,2)
    for k in 1:div(n, 2)
        j = n - k + 1
        # SWAP(k, j) decomposed into 3 CX gates
        push!(ops, GateOp(:CX, (k, j)))
        push!(ops, GateOp(:CX, (j, k)))
        push!(ops, GateOp(:CX, (k, j)))
    end

    return GateCircuit(ops, n)
end

"""
    toffoli_circuit()

3-qubit Toffoli (CCX) gate: flip qubit 3 iff qubits 1 and 2 are both |1⟩.
Represented as a single named gate — `compile_block` will synthesize a
native pulse, not a decomposition.
"""
toffoli_circuit() = GateCircuit([GateOp(:CCX, (1, 2, 3))], 3)

"""
    ccz_circuit()

3-qubit doubly-controlled Z gate: phase-flip |111⟩ only.
"""
ccz_circuit() = GateCircuit([GateOp(:CCZ, (1, 2, 3))], 3)

# ============================================================================ #
# Tests
# ============================================================================ #

@testitem "qft_circuit — 2-qubit" begin
    using LinearAlgebra
    c = qft_circuit(2)
    @test c isa GateCircuit
    @test c.n_qubits == 2
    @test length(c.ops) > 0

    # Unitarity check (smallest problem we test)
    U = circuit_unitary(c)
    @test U' * U ≈ I(4) atol=1e-10
end

@testitem "toffoli_circuit — 3-qubit unitary" begin
    using LinearAlgebra
    c = toffoli_circuit()
    @test c isa GateCircuit
    @test c.n_qubits == 3

    U = circuit_unitary(c)
    @test size(U) == (8, 8)
    @test U' * U ≈ I(8) atol=1e-12
    # Toffoli swaps |110⟩ (index 7) and |111⟩ (index 8), others identity
    @test U[7, 8] ≈ 1 atol=1e-12
    @test U[8, 7] ≈ 1 atol=1e-12
    @test U[7, 7] ≈ 0 atol=1e-12
end

@testitem "ccz_circuit — 3-qubit unitary" begin
    using LinearAlgebra
    c = ccz_circuit()
    U = circuit_unitary(c)
    @test size(U) == (8, 8)
    @test U' * U ≈ I(8) atol=1e-12
    # CCZ phase-flips |111⟩ only
    @test U[8, 8] ≈ -1 atol=1e-12
    @test U[7, 7] ≈ 1 atol=1e-12
end
