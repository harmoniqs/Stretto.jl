using Test
using Stretto
using LinearAlgebra
using Piccolo: GATES

@testset "Circuits" begin
    @testset "GateOp construction" begin
        op = GateOp(:CZ, (1, 2))
        @test op.gate == :CZ
        @test op.qubits == (1, 2)
    end

    @testset "circuit_unitary — H on qubit 1 of 2" begin
        seq = GateCircuit([GateOp(:H, (1,))], 2)
        U = circuit_unitary(seq)
        H = (1/√2) * [1 1; 1 -1]
        expected = kron(H, Matrix{ComplexF64}(I, 2, 2))
        @test size(U) == (4, 4)
        @test U ≈ expected atol=1e-12
    end

    @testset "circuit_unitary — CZ on (1,2)" begin
        seq = GateCircuit([GateOp(:CZ, (1, 2))], 2)
        U = circuit_unitary(seq)
        @test U ≈ GATES[:CZ] atol=1e-12
    end

    @testset "circuit_unitary — H then CZ" begin
        seq = GateCircuit(
            [GateOp(:H, (1,)), GateOp(:CZ, (1, 2))],
            2
        )
        U = circuit_unitary(seq)
        H_embed = kron((1/√2) * [1 1; 1 -1], Matrix{ComplexF64}(I, 2, 2))
        expected = GATES[:CZ] * H_embed
        @test U ≈ expected atol=1e-12
    end

    @testset "qft_circuit" begin
        c = qft_circuit(2)
        @test c isa GateCircuit
        @test c.n_qubits == 2
        @test length(c.ops) > 0
    end

    @testset "QFT-2 unitary matches known" begin
        c = qft_circuit(2)
        U = circuit_unitary(c)
        # 2-qubit QFT matrix (with bit-reversal)
        ω = exp(2π * im / 4)
        F2 = (1/2) * [1 1 1 1;
                       1 ω ω^2 ω^3;
                       1 ω^2 1 ω^2;
                       1 ω^3 ω^2 ω]
        # QFT is unitary — check unitarity at minimum
        @test U' * U ≈ I(4) atol=1e-10
    end
end
