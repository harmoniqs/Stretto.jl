"""
    from_qasm(qasm::String) -> GateCircuit

Parse an OpenQASM 3 string and return a `GateCircuit`.

The parser accepts a minimal subset of OpenQASM 3 covering all gates that Stretto
supports natively:

- **Single-qubit**: `h`, `x`, `y`, `z`, `s`, `t`, `sx`, `sdg`, `tdg`
- **Two-qubit**: `cx`, `cz`, `swap`
- **Three-qubit**: `ccx` (Toffoli)

Qubit indices in the QASM source are 0-based; `from_qasm` converts them to
Stretto's 1-based indexing automatically (e.g. `q[0]` → qubit `1`).

Only **static** gates are supported. Parametric gates such as `rz(θ)` are
out of scope per the upstream issue.

# Examples
```julia
julia> qasm = \"\"\"
       OPENQASM 3;
       qubit[2] q;
       h q[0];
       cx q[0], q[1];
       \"\"\"
       >>> from_qasm(qasm)
GateCircuit(GateOp[:H => (1,), :CX => (1, 2)], 2)

julia> from_qasm(read("bell.qasm", String))  # from a file
GateCircuit(GateOp[:H => (1,), :CX => (1, 2)], 2)
```

See also [`circuit_unitary`](@ref) and [`compile_block`](@ref).
"""
function from_qasm(qasm::String)
    ops = GateOp[]
    n_qubits = 0

    # Normalise: strip comments and collapse whitespace
    lines = split(String(qasm), '\n')
    for raw in lines
        line = String(strip(raw))
        isempty(line) && continue
        startswith(line, "//") && continue

        if occursin("OPENQASM", line)
            continue
        elseif occursin("include", line)
            # OPENQASM 3 includes are informational for this subset
            continue
        elseif occursin("qubit", line)
            n_qubits = _parse_qubit_decl(line)
        elseif occursin("bit", line) && !occursin("qubit", line)
            #古典 register declarations (e.g. `bit[2] c;`) — skip
            continue
        elseif occursin("barrier", line)
            # Barriers are no-ops for our purposes
            continue
        elseif occursin("reset", line)
            # Reset is a no-op for circuit unitary / compilation
            continue
        elseif occursin("measure", line)
            # Measurements are terminal in QASM; skip so we don't double-count
            continue
        elseif occursin("gate", line)
            # User-defined gates — skip for now (static gate subset only)
            continue
        else
            op = _try_parse_gate(line)
            if op !== nothing
                push!(ops, op)
            else
                @warn "Skipping unrecognised QASM line: $line"
            end
        end
    end

    if n_qubits == 0 && !isempty(ops)
        # Infer from highest qubit index seen
        n_qubits = maximum(q for op in ops for q in op.qubits)
    end

    return GateCircuit(ops, n_qubits)
end

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

"""
    _parse_qubit_decl(line::String) -> Int

Extract the number of qubits from a declaration like `qubit[5] q;`.
"""
function _parse_qubit_decl(line::String)
    m = match(r"qubit\s*\[\s*(\d+)\s*\]", line)
    m === nothing && return 0
    return parse(Int, m.captures[1])
end

"""
    _gate_name_map() -> Dict{String, Symbol}

Return the mapping from lowercase QASM gate names to Stretto `GateOp` symbols.
"""
function _gate_name_map()
    return Dict{String,Symbol}(
        # Single-qubit
        "h" => :H,
        "x" => :X,
        "y" => :Y,
        "z" => :Z,
        "s" => :S,
        "sdg" => :SDG,
        "t" => :T,
        "tdg" => :TDG,
        "sx" => :SX,
        # Two-qubit
        "cx" => :CX,
        "cz" => :CZ,
        "swap" => :SWAP,
        # Three-qubit
        "ccx" => :CCX,
        # Alias (CNOT is valid QASM, Stretto uses :CX internally)
        "cnot" => :CX,
    )
end

"""
    _try_parse_gate(line::String) -> Union{GateOp, Nothing}

Parse a single gate statement line like `h q[0];` or `cx q[0], q[1];`
and return a `GateOp`, or `nothing` if the line is not a gate.
"""
function _try_parse_gate(line::String)
    # Strip trailing semicolon
    line = String(rstrip(line, ';'))
    line = String(strip(line))

    # First, split gate name from its arguments (space-separated)
    space_parts = split(line, r"\s+")
    isempty(space_parts) && return nothing

    gate_name = lowercase(String(space_parts[1]))

    # Remove any gate modifiers (e.g. "ctrl @ h") — skip for now
    if occursin("@", gate_name) || occursin("inv", gate_name) || occursin("pow", gate_name)
        return nothing
    end

    name_map = _gate_name_map()
    gate_sym = get(name_map, gate_name, nothing)
    gate_sym === nothing && return nothing

    # Parse qubit arguments (comma-separated: `q[0], q[1], q[2]`)
    qubits = Int[]
    if length(space_parts) >= 2
        qubit_arg = join(space_parts[2:end], " ")
        qubit_parts = split(qubit_arg, r"\s*,\s*")
        for part in qubit_parts
            part = String(strip(part))
            m = match(r"q\s*\[\s*(\d+)\s*\]", part)
            if m === nothing
                # Named qubit reference — try generic index pattern
                m = match(r"\[\s*(\d+)\s*\]", part)
                m === nothing && continue
            end
            idx = parse(Int, m.captures[1]) + 1  # 0-based → 1-based
            push!(qubits, idx)
        end
    end

    isempty(qubits) && return GateOp(gate_sym, (1,))
    return GateOp(gate_sym, Tuple(qubits))
end
