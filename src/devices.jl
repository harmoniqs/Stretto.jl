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

    # Use composite's drive_bounds directly (already includes all subsystems)
    return QuantumSystem(H_drift, H_drives, composite.drive_bounds)
end
