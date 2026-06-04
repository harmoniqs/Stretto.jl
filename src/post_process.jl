"""
    default_post_process() -> Vector{Function}

Return the ordered list of post-processing transforms applied after a block
solve. Each entry has signature `(block_result, ctx::PostProcessContext) -> block_result'`.

Substrate: empty list (no post-processing). Strategies may override with
their own `post_process::Vector{Function}` via the CompilationStrategy struct;
this seam is the codebase-wide default consulted only when no strategy is
selected.
"""
default_post_process() = _DEFAULT_POST_PROCESS[]()
_substrate_default_post_process() = Function[]
const _DEFAULT_POST_PROCESS = Ref{Any}(_substrate_default_post_process)

"""
    set_default_post_process!(f)

Install `f` as the substrate post-process builder. `f` must have signature
`() -> Vector{Function}`.
"""
set_default_post_process!(f) = (_DEFAULT_POST_PROCESS[] = f)

# ============================================================================
# FFT Pulse-Spectrum Analyzer
# ============================================================================
# Core computation lives in post_process.jl; the Makie visualization is in
# ext/StrettoMakieExt.jl.  A stub is declared here so the extension can extend
# it without needing a separate file.

"""
    plot_pulse_spectrum(pulse; n_samples=1000, title=\"Pulse Spectrum\")

Plot the one-sided FFT power spectrum of a compiled control pulse.  Only
available when `CairoMakie` is loaded via `using StrettoMakieExt`.
"""
function plot_pulse_spectrum end

@testitem "PostProcessContext — basic construction" begin
    using Stretto
    using Piccolo: UnitaryTrajectory, CubicSplinePulse, QuantumSystem, SplinePulseProblem

    σz = ComplexF64[1 0; 0 -1];
    σx = ComplexF64[0 1; 1 0]
    sys = QuantumSystem(σz, [σx], [1.0])
    times = collect(range(0.0, 10.0, length = 5))
    pulse = CubicSplinePulse(
        zeros(1, 5),
        zeros(1, 5),
        times;
        initial_value = zeros(1),
        final_value = zeros(1),
    )
    qtraj = UnitaryTrajectory(sys, pulse, ComplexF64[1 0; 0 1])
    problem = SplinePulseProblem(qtraj; Q = 100.0)

    device = HeronR3()
    circuit = GateCircuit([GateOp(:H, (1,))], 1)

    ctx = Stretto.PostProcessContext(circuit, device, qtraj, problem)
    @test ctx.circuit === circuit
    @test ctx.device === device
    @test ctx.qtraj === qtraj
    @test ctx.problem === problem
end

@testitem "default_post_process — substrate is empty list" begin
    using Stretto

    pp = Stretto.default_post_process()
    @test pp isa Vector
    @test isempty(pp)
end

# ============================================================================
# FFT Pulse-Spectrum Analyzer
# ============================================================================

"""
    PulseSpectrum

Result of [`pulse_spectrum`](@ref): frequency-domain power spectrum of a pulse.
`n_drives` channels, each with `n_samples ÷ 2 + 1` one-sided frequency bins.

Fields:
- `freqs::Vector{Float64}` — frequency in GHz (positive half of FFT, DC to Nyquist)
- `power::Matrix{Float64}` — `n_drives × n_bins` one-sided power spectrum (V²/Hz)
- `n_drives::Int` — number of drive channels
- `dt_ns::Float64` — time step between samples in nanoseconds
"""
struct PulseSpectrum
    freqs::Vector{Float64}
    power::Matrix{Float64}
    n_drives::Int
    dt_ns::Float64
end

Base.size(ps::PulseSpectrum) = (ps.n_drives, length(ps.freqs))

"""
    pulse_spectrum(pulse; n_samples=1000)

Compute the one-sided FFT power spectrum of a compiled control pulse.

# Arguments
- `pulse::AbstractPulse`: the pulse to analyze (from `compile_block(...).pulse`)
- `n_samples::Int=1000`: number of time-domain samples for FFT resolution

# Returns
- `PulseSpectrum` with fields `freqs` (GHz) and `power` (`n_drives × n_bins` matrix)

# Details
- Samples the pulse via `Piccolo.sample(pulse, n_samples)` → `(controls, times)`
- Applies a Hann window to each drive channel to reduce spectral leakage
- Computes the one-sided power spectrum: `P = 2|nS|/n²` for positive frequencies
- Frequencies are in GHz because pulse duration is in ns (`freq_GHz = fftfreq(n, 1/dt)`)

# Example
```julia
using Stretto

result = compile_block(qft_circuit(2), HeronR3(), [1, 2])
spec = pulse_spectrum(result.pulse)

# Access results
spec.freqs   # frequency bins in GHz
spec.power   # n_drives × n_bins power matrix; spec.power[d,:] = channel d spectrum
```

See also [`plot_pulse_spectrum`](@ref) for visualization.
"""
function pulse_spectrum(pulse::AbstractPulse; n_samples::Int = 1000)
    n_samples >= 2 || throw(ArgumentError("n_samples must be >= 2, got $n_samples"))

    controls, times = Piccolo.sample(pulse, n_samples)
    n_drives = size(controls, 1)
    n = size(controls, 2)

    dt_ns = Float64(times[2] - times[1])

    # Hann window to reduce spectral leakage
    window = [0.5 * (1 - cos(2π * k / (n - 1))) for k in 0:(n-1)]

    # One-sided: 0 to Nyquist using rfft (real input → positive freq only)
    n_pos = div(n, 2) + 1
    freqs = range(0.0, 1.0 / (2 * dt_ns), length = n_pos)
    power = zeros(n_drives, n_pos)

    for d in 1:n_drives
        signal = @view controls[d, :]
        windowed = signal .* window
        # rfft returns only positive frequencies (DC to Nyquist) for real input
        S = FFTW.rfft(windowed)
        # One-sided power: DC unchanged, positive freq bins scaled by 2 (except Nyquist)
        power[d, 1] = abs2(S[1]) / (n^2)
        @inbounds @simd for k in 2:(n_pos - 1)
            power[d, k] = 2.0 * abs2(S[k]) / (n^2)
        end
        @inbounds power[d, n_pos] = abs2(S[n_pos]) / (n^2)
    end

    return PulseSpectrum(freqs, power, n_drives, dt_ns)
end

@testitem "pulse_spectrum — sinusoidal pulse has peak at driving frequency" begin
    using Stretto
    using FFTW

    # Build a simple sinusoidal pulse at known frequency
    ω::Float64 = 0.5  # GHz (driving frequency)
    T::Float64 = 50.0  # ns (pulse duration)
    n_samples::Int = 1024
    times = collect(range(0.0, T, length = n_samples))
    phases = 2π * ω .* times

    controls = Matrix{Float64}(undef, 1, n_samples)
    controls[1, :] = sin.(phases)

    pulse = CubicSplinePulse(controls, controls, times)

    spec = pulse_spectrum(pulse; n_samples = n_samples)

    @test spec isa PulseSpectrum
    @test spec.n_drives == 1
    @test size(spec.power) == (1, div(n_samples, 2) + 1)
    @test length(spec.freqs) == div(n_samples, 2) + 1
    @test spec.freqs[1] ≈ 0.0 atol = 1e-6  # DC bin

    # Peak should be near ω (within frequency resolution: 1/T = 0.02 GHz)
    peak_idx = argmax(spec.power[1, :])
    peak_freq = spec.freqs[peak_idx]
    @test peak_freq ≈ ω atol = (1.0 / T) + 1e-3
end

@testitem "pulse_spectrum — multi-channel pulse returns per-channel spectra" begin
    using Stretto

    # 2-drive pulse with two different driving frequencies
    n_drives = 2
    n_samples = 512
    times = collect(range(0.0, 100.0, length = n_samples))
    controls = Matrix{Float64}(undef, n_drives, n_samples)
    controls[1, :] = sin.(2π * 0.3 .* times)
    controls[2, :] = cos.(2π * 0.7 .* times)

    pulse = CubicSplinePulse(controls, controls, times)
    spec = pulse_spectrum(pulse; n_samples = n_samples)

    @test spec.n_drives == n_drives
    @test size(spec.power) == (n_drives, div(n_samples, 2) + 1)

    # Each channel's peak should be near its driving frequency
    peak1 = spec.freqs[argmax(spec.power[1, :])]
    peak2 = spec.freqs[argmax(spec.power[2, :])]
    @test peak1 ≈ 0.3 atol = 0.1
    @test peak2 ≈ 0.7 atol = 0.1
end

@testitem "pulse_spectrum — rejects n_samples < 2" begin
    using Stretto
    pulse = CubicSplinePulse(zeros(1, 2), zeros(1, 2), [0.0, 1.0])
    @test_throws ArgumentError pulse_spectrum(pulse; n_samples = 1)
end
