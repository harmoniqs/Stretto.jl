using TestItems: @testitem
using LinearAlgebra

@testitem "from_qasm — Bell state (h + cx)" begin
    using Stretto: from_qasm, GateOp

    qasm = """
    OPENQASM 3;
    qubit[2] q;
    h q[0];
    cx q[0], q[1];
    """

    circuit = from_qasm(qasm)
    @test circuit.n_qubits == 2
    @test length(circuit.ops) == 2
    @test circuit.ops[1] == GateOp(:H, (1,))
    @test circuit.ops[2] == GateOp(:CX, (1, 2))
end

@testitem "from_qasm — SWAP gate" begin
    using Stretto: from_qasm, GateOp

    qasm = """
    OPENQASM 3;
    qubit[2] q;
    swap q[0], q[1];
    """

    circuit = from_qasm(qasm)
    @test circuit.n_qubits == 2
    @test circuit.ops[1] == GateOp(:SWAP, (1, 2))
end

@testitem "from_qasm — Toffoli (ccx)" begin
    using Stretto: from_qasm, GateOp

    qasm = """
    OPENQASM 3;
    qubit[3] q;
    ccx q[0], q[1], q[2];
    """

    circuit = from_qasm(qasm)
    @test circuit.n_qubits == 3
    @test circuit.ops[1] == GateOp(:CCX, (1, 2, 3))
end

@testitem "from_qasm — CZ gate" begin
    using Stretto: from_qasm, GateOp

    qasm = """
    OPENQASM 3;
    qubit[2] q;
    cz q[0], q[1];
    """

    circuit = from_qasm(qasm)
    @test circuit.n_qubits == 2
    @test circuit.ops[1] == GateOp(:CZ, (1, 2))
end

@testitem "from_qasm — single-qubit gates (X, Y, Z, S, T, SX)" begin
    using Stretto: from_qasm, GateOp

    qasm = """
    OPENQASM 3;
    qubit[1] q;
    x q[0];
    y q[0];
    z q[0];
    s q[0];
    t q[0];
    sx q[0];
    """

    circuit = from_qasm(qasm)
    @test circuit.n_qubits == 1
    @test length(circuit.ops) == 6
    @test circuit.ops[1] == GateOp(:X, (1,))
    @test circuit.ops[2] == GateOp(:Y, (1,))
    @test circuit.ops[3] == GateOp(:Z, (1,))
    @test circuit.ops[4] == GateOp(:S, (1,))
    @test circuit.ops[5] == GateOp(:T, (1,))
    @test circuit.ops[6] == GateOp(:SX, (1,))
end

@testitem "from_qasm — SDG and TDG (adjoint gates)" begin
    using Stretto: from_qasm, GateOp

    qasm = """
    OPENQASM 3;
    qubit[1] q;
    sdg q[0];
    tdg q[0];
    """

    circuit = from_qasm(qasm)
    @test circuit.n_qubits == 1
    @test length(circuit.ops) == 2
    @test circuit.ops[1] == GateOp(:SDG, (1,))
    @test circuit.ops[2] == GateOp(:TDG, (1,))
end

@testitem "from_qasm — cnot alias" begin
    using Stretto: from_qasm, GateOp

    qasm = """
    OPENQASM 3;
    qubit[2] q;
    cnot q[0], q[1];
    """

    circuit = from_qasm(qasm)
    @test circuit.n_qubits == 2
    @test circuit.ops[1] == GateOp(:CX, (1, 2))
end

@testitem "from_qasm — round-trip via circuit_unitary" begin
    using Stretto: from_qasm, circuit_unitary
    using LinearAlgebra

    qasm = """
    OPENQASM 3;
    qubit[2] q;
    h q[0];
    cx q[0], q[1];
    """

    circuit = from_qasm(qasm)
    U = circuit_unitary(circuit)

    # Bell state: (|00⟩ + |11⟩)/√2
    @test size(U) == (4, 4)
    @test U' * U ≈ I(4) atol=1e-12
    # Column 0 (|00⟩) should map to Bell column
    @test U[:, 1] ≈ ComplexF64[1, 0, 0, 1] / √2 atol=1e-12
end

@testitem "from_qasm — round-trip for SWAP unitary" begin
    using Stretto: from_qasm, circuit_unitary
    using LinearAlgebra

    qasm = """
    OPENQASM 3;
    qubit[2] q;
    swap q[0], q[1];
    """

    circuit = from_qasm(qasm)
    U = circuit_unitary(circuit)

    # SWAP matrix
    expected = ComplexF64[1 0 0 0; 0 0 1 0; 0 1 0 0; 0 0 0 1]
    @test U ≈ expected atol=1e-12
    @test U' * U ≈ I(4) atol=1e-12
end

@testitem "from_qasm — comments and blank lines are ignored" begin
    using Stretto: from_qasm, GateOp

    qasm = """
    // This is a comment
    OPENQASM 3;
    qubit[2] q;

    // Another comment
    h q[0];  // inline comment

    cx q[0], q[1];
    """

    circuit = from_qasm(qasm)
    @test circuit.n_qubits == 2
    @test length(circuit.ops) == 2
    @test circuit.ops[1] == GateOp(:H, (1,))
    @test circuit.ops[2] == GateOp(:CX, (1, 2))
end

@testitem "from_qasm — measures and barriers are skipped" begin
    using Stretto: from_qasm, GateOp

    qasm = """
    OPENQASM 3;
    qubit[2] q;
    bit[2] c;
    h q[0];
    cx q[0], q[1];
    barrier q[0], q[1];
    measure q[0] -> c[0];
    measure q[1] -> c[1];
    """

    circuit = from_qasm(qasm)
    @test circuit.n_qubits == 2
    @test length(circuit.ops) == 2
    @test circuit.ops[1] == GateOp(:H, (1,))
    @test circuit.ops[2] == GateOp(:CX, (1, 2))
end

@testitem "from_qasm — CNOT alias (capitalisation)" begin
    using Stretto: from_qasm, GateOp

    # Mixed case should work
    qasm = """
    OPENQASM 3;
    qubit[2] q;
    CX q[0], q[1];
    """

    circuit = from_qasm(qasm)
    @test circuit.ops[1] == GateOp(:CX, (1, 2))
end

@testitem "from_qasm — multi-gate sequence matches library circuit" begin
    using Stretto: from_qasm, bell_circuit, circuit_unitary

    # from_qasm should produce equivalent circuit to library
    qasm = """
    OPENQASM 3;
    qubit[2] q;
    h q[0];
    cx q[0], q[1];
    """

    parsed = from_qasm(qasm)
    expected = bell_circuit()

    U_parsed = circuit_unitary(parsed)
    U_expected = circuit_unitary(expected)

    @test U_parsed ≈ U_expected atol=1e-12
end
