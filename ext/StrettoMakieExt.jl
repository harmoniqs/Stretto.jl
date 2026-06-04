module StrettoMakieExt

using Stretto
using CairoMakie

using Stretto: PulseSpectrum, pulse_spectrum
using Piccolo: n_drives, duration, sample

# Docstring lives on the stub in src/post_process.jl.
# This file only provides the Makie-powered implementation.

const _CHANNEL_PALETTE = [
    :blue, :red, :green, :orange, :purple, :cyan,
    :magenta, :yellow, :black, :brown,
]

function _plot_spectrum(spec::PulseSpectrum; title::String = "Pulse Spectrum")
    n_channels = spec.n_drives
    n_bins = length(spec.freqs)

    fig = Figure(; size = (800, 300 + 80 * n_channels))
    ax = Axis(
        fig[1, 1];
        xlabel = "Frequency (GHz)",
        ylabel = "Power (V²/Hz)",
        title = title,
        yscale = log10,
        yminorticksvisible = true,
        yminorgridstepsvisible = true,
    )

    xlims!(ax, spec.freqs[1], spec.freqs[end])
    colormap = _CHANNEL_PALETTE

    for d in 1:n_channels
        color = colormap[mod1(d, length(colormap))]
        label = "Drive $(d)"
        lines!(ax, spec.freqs, spec.power[d, :]; color, label, linewidth = 1.5)
    end

    axislegend(ax; position = :rt, rowgap = 5)

    return fig
end

function _plot_spectrum_from_pulse(pulse; title::String = "Pulse Spectrum", kwargs...)
    spec = pulse_spectrum(pulse; kwargs...)
    return _plot_spectrum(spec; title)
end

"""
    plot_pulse_spectrum(pulse; n_samples=1000, title=\"Pulse Spectrum\")

Plot the one-sided FFT power spectrum of a compiled control pulse using CairoMakie.
Returns a `Figure` with all drive channels overlaid on a shared axis.

This function is only available when `CairoMakie` is loaded (via the
`StrettoMakieExt` extension). Install with `] add CairoMakie`.

# Arguments
- `pulse`: an `AbstractPulse` (from `compile_block(...).pulse`)
- `n_samples::Int=1000`: number of FFT samples
- `title::String="Pulse Spectrum"`: figure title

# Returns
- `CairoMakie.Figure`

# Example
```julia
using Stretto

result = compile_block(qft_circuit(2), HeronR3(), [1, 2])
fig = plot_pulse_spectrum(result.pulse)
display(fig)
```
"""
plot_pulse_spectrum(pulse; n_samples::Int = 1000, title::String = "Pulse Spectrum") =
    _plot_spectrum_from_pulse(pulse; title, n_samples)

end  # module
