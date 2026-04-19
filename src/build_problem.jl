"""
    PostProcessContext(circuit, device, qtraj, problem)

Carries the inter-stage state needed by `post_process` transforms.
Passed to each entry of a strategy's `post_process::Vector{Function}` list.
"""
struct PostProcessContext
    circuit::AbstractCircuit
    device::AbstractDevice
    qtraj::Any      # UnitaryTrajectory, but avoid tight type binding at compile-time
    problem::Any    # AbstractPiccoloProblem
end
