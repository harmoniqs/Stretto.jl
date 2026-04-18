module StrettoPiccolissimoExt

using Stretto
using Piccolissimo: SplineIntegrator

# Extensions cannot directly override methods whose arguments are all owned by
# parent packages (Piccolo's UnitaryTrajectory, Base's Int). Instead, we install
# a Piccolissimo-flavored builder into Stretto's Ref-held default at extension
# load time. See Stretto.default_integrator.
function __init__()
    Stretto.set_default_integrator!((qtraj, N) -> SplineIntegrator(qtraj, N))
    return nothing
end

end # module
