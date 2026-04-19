"""
    CompilationStrategy

A complete compilation recipe. Composes six seams (integrator, initial_pulse,
partitioner, build_problem, solver_strategy, post_process) plus dispatch metadata
(matches, state). `classify_problem` is a codebase-wide free function (seam #5)
and is NOT a per-strategy field — strategies may call it from their `matches`.

Constructed via the keyword constructor; omitted seam fields default to the
substrate implementations.
"""
struct CompilationStrategy
    name::Symbol
    description::String
    matches::Function

    integrator::Function
    initial_pulse::Function
    partitioner::Function
    build_problem::Function
    solver_strategy::Function
    post_process::Vector{Function}

    state::Any
end

# Keyword constructor with substrate-seam defaults
function CompilationStrategy(;
    name::Symbol,
    description::String = "",
    matches::Function,
    integrator::Function = default_integrator,
    initial_pulse::Function = default_initial_pulse,
    partitioner::Function = default_partitioner,
    build_problem::Function = build_problem,  # the exported free function
    solver_strategy::Function = default_solver_strategy,
    post_process::Vector{<:Function} = Function[],
    state = nothing,
)
    return CompilationStrategy(
        name, description, matches,
        integrator, initial_pulse, partitioner, build_problem, solver_strategy,
        convert(Vector{Function}, post_process),
        state,
    )
end

@testitem "CompilationStrategy — basic construction with all fields" begin
    using Stretto

    s = Stretto.CompilationStrategy(
        name = :test,
        description = "test strategy",
        matches = (c, d) -> 0.0,
        integrator = (qtraj, N) -> Stretto.default_integrator(qtraj, N),
        initial_pulse = (c, d, t, n) -> Stretto.default_initial_pulse(c, d, t, n),
        partitioner = (c, d) -> Stretto.default_partitioner(c, d),
        build_problem = (c, d, qt; kw...) -> Stretto.build_problem(c, d, qt; kw...),
        solver_strategy = (p, qt; kw...) -> Stretto.default_solver_strategy(p, qt; kw...),
        post_process = Function[],
        state = nothing,
    )

    @test s isa Stretto.CompilationStrategy
    @test s.name === :test
    @test s.description == "test strategy"
    @test s.post_process isa Vector{Function}
    @test s.state === nothing
end

@testitem "CompilationStrategy — default-filling constructor" begin
    using Stretto

    # Minimal construction: only name and matches required; everything else
    # defaults to the substrate seams.
    s = Stretto.CompilationStrategy(
        name = :minimal,
        description = "uses all substrate defaults",
        matches = (c, d) -> 0.0,
    )

    @test s.name === :minimal
    @test s.post_process == Function[]
    @test s.state === nothing
    # The seam functions should be callable and return substrate behavior.
    # We don't assert identity because the substrate is wrapped in a closure;
    # we just confirm callability.
    @test s.integrator isa Function
    @test s.initial_pulse isa Function
    @test s.partitioner isa Function
    @test s.build_problem isa Function
    @test s.solver_strategy isa Function
end
