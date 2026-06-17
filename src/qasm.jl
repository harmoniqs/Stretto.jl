#from_qasm(qasm::String) --> GateCircuit

#Parses a minimal subset of OpenQASM 3 string and returns a `GateCircuit`. Extracts qubit declarations (e.g., `qubit[2] q;`) and standard static gates.
# 0-based OpenQASM indices to 1-based Stretto indices.

function from_qasm(qasm::String)
    lines = split(qasm, '\n')
    num_qubits = 0
    ops = GateOp[]
    
    # Mapping of standard OpenQASM gate strings to Stretto's GateOp symbols
    gate_map = Dict(
        "h" => :H,
        "x" => :X,
        "y" => :Y,
        "z" => :Z,
        "s" => :S,
        "t" => :T,
        "cx" => :CX,
        "cz" => :CZ,
        "ccx" => :CCX
    )
    
    for line in lines
        # Clean line: safely remove inline comments
        parts = split(line, "//")
        clean_line = strip(parts[1])
        
        # Remove trailing semicolon and re-strip
        if endswith(clean_line, ";")
            clean_line = strip(clean_line[1:end-1])
        end
        
        # Skip empty lines and headers
        isempty(clean_line) && continue
        startswith(clean_line, "OPENQASM") && continue
        startswith(clean_line, "include") && continue
        
        # Parse qubit declaration (e.g., "qubit[2] q")
        m_qubit = match(r"qubit\s*\[(\d+)\]", clean_line)
        if m_qubit !== nothing
            num_qubits += parse(Int, m_qubit.captures[1])
            continue
        end
        
        # Parse gate operations
        # Split by the first space to separate the gate name from its target indices
        tokens = split(clean_line, " ", limit=2)
        if length(tokens) == 2
            gate_name = lowercase(strip(tokens[1]))
            
            if haskey(gate_map, gate_name)
                # Extract all numerical indices inside brackets dynamically
                indices_matches = eachmatch(r"\[(\d+)\]", tokens[2])
                
                # Apply +1 offset to convert from QASM (0-based) to Stretto (1-based)
                indices = [parse(Int, m.captures[1]) + 1 for m in indices_matches]
                
                if !isempty(indices)
                    push!(ops, GateOp(gate_map[gate_name], Tuple(indices)))
                end
            end
        end
    end
    
    # Fallback bounds check if the user omitted a clear qubit declaration
    if num_qubits == 0 && !isempty(ops)
        max_idx = 0
        for op in ops
            max_idx = max(max_idx, maximum(op.qubits))
        end
        num_qubits = max_idx
    end
    
    return GateCircuit(ops, num_qubits)
end