"""
    AbstractCircuit

Base type for quantum circuits in Stretto.
"""
abstract type AbstractCircuit end

"""
    GateOp(gate::Symbol, qubits::Tuple{Vararg{Int}})

A gate operation: gate name + qubit indices (1-based).
Gate names map to Piccolo's `GATES` via `resolve_gate`.
"""
struct GateOp
    gate::Symbol
    qubits::Tuple{Vararg{Int}}
end

GateOp(gate::Symbol, qubit::Int) = GateOp(gate, (qubit,))

"""
    GateCircuit(ops, n_qubits)

Ordered sequence of gate operations on `n_qubits` qubits.
Gates applied left-to-right: ops[1] first on the state.
"""
struct GateCircuit <: AbstractCircuit
    ops::Vector{GateOp}
    n_qubits::Int
end

Base.length(c::GateCircuit) = length(c.ops)

# Gate alias table: user-friendly names → GATES keys
const GATE_ALIASES = Dict{Symbol,Symbol}(
    :CNOT => :CX,
)

# Standard rotation gates not in Piccolo's GATES
const EXTRA_GATES = Dict{Symbol,Matrix{ComplexF64}}(
    :S  => ComplexF64[1 0; 0 im],
    :T  => ComplexF64[1 0; 0 exp(im*π/4)],
    :Rz => ComplexF64[1 0; 0 1],  # placeholder, overridden by Rz(θ)
)

"""Resolve a gate symbol to its unitary matrix."""
function resolve_gate(gate::Symbol)
    key = get(GATE_ALIASES, gate, gate)
    haskey(GATES, key) && return Matrix{ComplexF64}(GATES[key])
    haskey(EXTRA_GATES, key) && return EXTRA_GATES[key]
    error("Unknown gate :$gate. Available: $(keys(GATES)), $(keys(EXTRA_GATES))")
end

"""Controlled-phase gate CP(θ) = diag(1, 1, 1, e^{iθ})."""
function cp_gate(θ::Real)
    return ComplexF64[
        1 0 0 0;
        0 1 0 0;
        0 0 1 0;
        0 0 0 exp(im * θ)
    ]
end

"""
    kron_embed(gate_matrix, qubits, n_qubits)

Embed a gate into a multi-qubit Hilbert space.
Qubit 1 is most significant (leftmost in kron).
"""
function kron_embed(gate::AbstractMatrix, qubits::Tuple{Vararg{Int}}, n_qubits::Int)
    n_gate = length(qubits)
    d = 2

    # Trivial case: gate already on all qubits in order
    if n_gate == n_qubits && qubits == Tuple(1:n_qubits)
        return Matrix{ComplexF64}(gate)
    end

    # Single-qubit: direct kron
    if n_gate == 1
        q = qubits[1]
        factors = [i == q ? Matrix{ComplexF64}(gate) : Matrix{ComplexF64}(I, d, d)
                   for i in 1:n_qubits]
        return reduce(kron, factors)
    end

    # Adjacent multi-qubit in order: kron with identity padding
    if qubits == Tuple(qubits[1]:qubits[1]+n_gate-1)
        before = qubits[1] - 1
        after = n_qubits - qubits[end]
        factors = AbstractMatrix{ComplexF64}[]
        before > 0 && push!(factors, Matrix{ComplexF64}(I, d^before, d^before))
        push!(factors, Matrix{ComplexF64}(gate))
        after > 0 && push!(factors, Matrix{ComplexF64}(I, d^after, d^after))
        return reduce(kron, factors)
    end

    # General case: build by computational basis action
    D = d^n_qubits
    U = zeros(ComplexF64, D, D)
    for col in 0:D-1
        bits = digits(col, base=d, pad=n_qubits) |> reverse
        gate_bits = [bits[q] for q in qubits]
        gate_idx = sum(gate_bits[k] * d^(n_gate - k) for k in 1:n_gate)

        for out_gate_idx in 0:d^n_gate-1
            amp = gate[out_gate_idx+1, gate_idx+1]
            iszero(amp) && continue
            out_gate_bits = digits(out_gate_idx, base=d, pad=n_gate) |> reverse
            out_bits = copy(bits)
            for (k, q) in enumerate(qubits)
                out_bits[q] = out_gate_bits[k]
            end
            out_col = sum(out_bits[k] * d^(n_qubits - k) for k in 1:n_qubits)
            U[out_col+1, col+1] += amp
        end
    end
    return U
end

"""
    circuit_unitary(circuit::GateCircuit)

Compute the unitary matrix for a gate circuit.
Gates applied left-to-right, so matrix product is right-to-left.
"""
function circuit_unitary(circuit::GateCircuit)
    D = 2^circuit.n_qubits
    U = Matrix{ComplexF64}(I, D, D)
    for op in circuit.ops
        gate_mat = resolve_gate(op.gate)
        U = kron_embed(gate_mat, op.qubits, circuit.n_qubits) * U
    end
    return U
end
