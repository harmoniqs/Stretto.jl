"""
A qubit on a transmon device with its physical parameters.
"""
struct TransmonQubit
    ω::Float64    # frequency (GHz)
    δ::Float64    # anharmonicity (GHz), positive convention (Piccolo subtracts)
    n_levels::Int # number of levels (typically 3)
end

"""
A coupling edge between two qubits on a transmon device.
"""
struct CouplingEdge
    i::Int         # qubit index (1-based)
    j::Int         # qubit index (1-based)
    g::Float64     # coupling strength (GHz)
end

"""
Published performance data for a native gate on the device.
"""
struct GateSpec
    duration_ns::Float64
    error_rate::Float64
end

"""
    AbstractDevice

Base type for all hardware device profiles. Subtypes carry the physical
parameters needed to build a `QuantumSystem` for any qubit subset.
"""
abstract type AbstractDevice end

"""
    TransmonDevice <: AbstractDevice

A superconducting transmon device with published specs.
"""
struct TransmonDevice <: AbstractDevice
    name::String
    qubits::Vector{TransmonQubit}
    edges::Vector{CouplingEdge}
    native_gates::Dict{Symbol, GateSpec}
    drive_max::Float64                   # max drive amplitude (GHz)
    T1::Vector{Float64}                  # T1 per qubit (μs)
    T2::Vector{Float64}                  # T2 per qubit (μs)
end

"""Return subsystem levels for a qubit subset of a device."""
subsystem_levels(device::TransmonDevice, qubit_indices) =
    [device.qubits[i].n_levels for i in qubit_indices]

"""
    QuantumSystem(device::TransmonDevice, qubit_indices::AbstractVector{Int})

Build a Piccolo QuantumSystem for a subset of qubits on a transmon device.
Uses MultiTransmonSystem internally, then converts CompositeQuantumSystem
to a flat QuantumSystem with energy shift for ODE stability.
"""
function Piccolo.QuantumSystem(device::TransmonDevice, qubit_indices::AbstractVector{Int})
    n = length(qubit_indices)
    qs = [device.qubits[i] for i in qubit_indices]

    ωs = Float64[q.ω for q in qs]
    δs = Float64[q.δ for q in qs]

    # Build coupling matrix for the subset
    gs = zeros(Float64, n, n)
    for edge in device.edges
        # Map global indices to local indices
        li = findfirst(==(edge.i), qubit_indices)
        lj = findfirst(==(edge.j), qubit_indices)
        if !isnothing(li) && !isnothing(lj)
            gs[li, lj] = edge.g
            gs[lj, li] = edge.g
        end
    end

    levels = qs[1].n_levels  # assume uniform
    composite = MultiTransmonSystem(
        ωs, δs, gs;
        drive_bounds = device.drive_max,
        levels_per_transmon = levels,
    )

    # Convert CompositeQuantumSystem → QuantumSystem
    H_drift = Matrix{ComplexF64}(composite.H_drift)
    H_drives = [Matrix{ComplexF64}(H) for H in composite.H_drives]

    # Energy shift for ODE stability
    evals = real.(eigvals(Hermitian(H_drift)))
    Ē = (maximum(evals) + minimum(evals)) / 2
    H_drift .-= Ē * I(size(H_drift, 1))

    # Expand drive_bounds to match the number of drives.
    # MultiTransmonSystem returns 2 bounds per-subsystem but H_drives includes
    # all subsystem drives + coupling drives; pad/extend as needed.
    n_drv = length(H_drives)
    base_bounds = composite.drive_bounds
    drive_bounds = if length(base_bounds) == n_drv
        base_bounds
    elseif length(base_bounds) == 1
        fill(base_bounds[1], n_drv)
    else
        # Cycle the pattern to cover all drives (e.g., [(-b,b),(-b,b)] → repeated per qubit)
        [base_bounds[mod1(i, length(base_bounds))] for i in 1:n_drv]
    end

    return QuantumSystem(H_drift, H_drives, drive_bounds)
end

# ============================================================================ #
# Tests
# ============================================================================ #

@testitem "HeronR3 construction" begin
    device = HeronR3()
    @test device isa TransmonDevice
    @test device.name == "ibm_heron_r3"
    @test length(device.qubits) >= 4
end

@testitem "QuantumSystem from 2-qubit subset" begin
    using Piccolo: QuantumSystem
    device = HeronR3()
    sys = QuantumSystem(device, [1, 2])
    @test sys isa QuantumSystem
    # 2 transmons × 3 levels = 9 dim
    @test size(sys.H_drift, 1) == 9
    # 2 drives per transmon = 4 drives
    @test length(sys.H_drives) == 4
end

@testitem "subsystem_levels accessor" begin
    device = HeronR3()
    @test Stretto.subsystem_levels(device, [1, 2]) == [3, 3]
end
