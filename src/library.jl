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
