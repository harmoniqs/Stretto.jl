using Test
using Stretto
using Piccolo: QuantumSystem

@testset "Devices" begin
    @testset "HeronR3 construction" begin
        device = HeronR3()
        @test device isa TransmonDevice
        @test device.name == "ibm_heron_r3"
        @test length(device.qubits) >= 4
    end

    @testset "QuantumSystem from 2-qubit subset" begin
        device = HeronR3()
        sys = QuantumSystem(device, [1, 2])
        @test sys isa QuantumSystem
        # 2 transmons × 3 levels = 9 dim
        @test size(sys.H_drift, 1) == 9
        # 2 drives per transmon = 4 drives
        @test length(sys.H_drives) == 4
    end

    @testset "QuantumSystem from 4-qubit subset" begin
        device = HeronR3()
        sys = QuantumSystem(device, [1, 2, 3, 4])
        @test sys isa QuantumSystem
        # 4 transmons × 3 levels = 81 dim
        @test size(sys.H_drift, 1) == 81
        # 4 × 2 = 8 drives
        @test length(sys.H_drives) == 8
    end

    @testset "subsystem_levels accessor" begin
        device = HeronR3()
        @test Stretto.subsystem_levels(device, [1, 2]) == [3, 3]
        @test Stretto.subsystem_levels(device, [1, 2, 3, 4]) == [3, 3, 3, 3]
    end
end
