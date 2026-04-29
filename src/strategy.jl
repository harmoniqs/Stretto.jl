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
        name,
        description,
        matches,
        integrator,
        initial_pulse,
        partitioner,
        build_problem,
        solver_strategy,
        convert(Vector{Function}, post_process),
        state,
    )
end

# ---------------------------------------------------------------------------- #
# Registry
# ---------------------------------------------------------------------------- #

const _STRATEGY_REGISTRY = Dict{Symbol,CompilationStrategy}()

"""
    register_strategy!(s::CompilationStrategy)

Register `s` under `s.name`. If a strategy with that name already exists, warn
and overwrite. Returns `s`.
"""
function register_strategy!(s::CompilationStrategy)
    if haskey(_STRATEGY_REGISTRY, s.name)
        @warn "overwriting strategy :$(s.name)"
    end
    _STRATEGY_REGISTRY[s.name] = s
    return s
end

"""
    unregister_strategy!(name::Symbol)

Remove the strategy with the given name from the registry. No-op if absent.
"""
unregister_strategy!(name::Symbol) = (delete!(_STRATEGY_REGISTRY, name); nothing)

"""
    strategies() -> Dict{Symbol, CompilationStrategy}

Return a copy of the current strategy registry. Safe to iterate; mutating the
returned Dict does not affect the live registry.
"""
strategies() = copy(_STRATEGY_REGISTRY)

# ---------------------------------------------------------------------------- #
# Dispatch
# ---------------------------------------------------------------------------- #

"""
    select_strategy(circuit, device) -> CompilationStrategy

Score every registered strategy except `:default` via its `matches` function.
Return the highest-scoring strategy if its score is strictly greater than 0.0.
Otherwise return the `:default` strategy as fallback.

`:default` is excluded from the scoring pool — it's the sentinel fallback,
not a competitor at score 0.

Ties at the top score resolve by registration order (Julia's `Dict` iteration
is insertion-ordered as of 1.9+; first registered wins).
"""
function select_strategy(circuit, device)
    default = get(_STRATEGY_REGISTRY, :default, nothing)
    default === nothing &&
        error("no :default strategy registered — Stretto module did not load correctly")

    best::Union{CompilationStrategy,Nothing} = nothing
    best_score = 0.0

    for s in values(_STRATEGY_REGISTRY)
        s.name === :default && continue
        score = s.matches(circuit, device)
        if score > best_score
            best_score = score
            best = s
        end
    end

    return best === nothing ? default : best
end

# ---------------------------------------------------------------------------- #
# :default strategy — substrate composition, sentinel fallback
# ---------------------------------------------------------------------------- #

"""
The `:default` strategy composes all substrate seams and matches nothing (score
0.0 on every input). It's excluded from `select_strategy`'s scoring pool and
used as the fallback when no strategy scores above 0.0.

Byte-for-byte equivalent to Stretto v0.2.1's `compile_block` behavior.
"""
const DEFAULT_STRATEGY = CompilationStrategy(
    name = :default,
    description = "Substrate: cold-start, whole-circuit, BilinearIntegrator. Fallback sentinel.",
    matches = (circuit, device) -> 0.0,
    # All other fields take their keyword-constructor defaults (substrate seams).
)

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
        solver_strategy = (p, qt; kw...) ->
            Stretto.default_solver_strategy(p, qt; kw...),
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

@testitem "strategy registry — register / unregister / list" begin
    using Stretto

    # Snapshot initial registry state (:default may be present if Task 7 landed)
    initial = copy(Stretto.strategies())

    s = Stretto.CompilationStrategy(
        name = :test_register,
        description = "registry test",
        matches = (c, d) -> 0.0,
    )

    returned = Stretto.register_strategy!(s)
    @test returned === s
    @test haskey(Stretto.strategies(), :test_register)
    @test Stretto.strategies()[:test_register] === s

    Stretto.unregister_strategy!(:test_register)
    @test !haskey(Stretto.strategies(), :test_register)

    # Confirm we didn't disturb :default or anything else
    @test keys(Stretto.strategies()) == keys(initial)
end

@testitem "strategy registry — overwrite warning" begin
    using Stretto

    s1 = Stretto.CompilationStrategy(
        name = :test_overwrite,
        description = "first",
        matches = (c, d) -> 0.0,
    )
    s2 = Stretto.CompilationStrategy(
        name = :test_overwrite,
        description = "second",
        matches = (c, d) -> 0.0,
    )

    Stretto.register_strategy!(s1)
    # Second register should warn, not throw
    @test_logs (:warn, r"overwriting strategy") Stretto.register_strategy!(s2)
    @test Stretto.strategies()[:test_overwrite].description == "second"

    Stretto.unregister_strategy!(:test_overwrite)
end

@testitem "select_strategy — falls back to :default when pool is empty" begin
    using Stretto

    # Register only :default (Task 7 will do this at module load; here we
    # emulate by clearing and re-registering a minimal default).
    for name in collect(keys(Stretto.strategies()))
        name == :default || Stretto.unregister_strategy!(name)
    end

    # Ensure :default exists for this test (created here if Task 7 hasn't landed)
    if !haskey(Stretto.strategies(), :default)
        Stretto.register_strategy!(
            Stretto.CompilationStrategy(
                name = :default,
                description = "test-only default placeholder",
                matches = (c, d) -> 0.0,
            ),
        )
    end

    device = HeronR3()
    circuit = GateCircuit([GateOp(:H, (1,))], 1)

    selected = Stretto.select_strategy(circuit, device)
    @test selected.name === :default
end

@testitem "select_strategy — picks highest-scoring non-default strategy" begin
    using Stretto

    device = HeronR3()
    circuit = GateCircuit([GateOp(:H, (1,))], 1)

    low = Stretto.CompilationStrategy(
        name = :low_score,
        description = "",
        matches = (c, d) -> 0.1,
    )
    high = Stretto.CompilationStrategy(
        name = :high_score,
        description = "",
        matches = (c, d) -> 0.9,
    )
    Stretto.register_strategy!(low)
    Stretto.register_strategy!(high)

    selected = Stretto.select_strategy(circuit, device)
    @test selected.name === :high_score

    Stretto.unregister_strategy!(:low_score)
    Stretto.unregister_strategy!(:high_score)
end

@testitem "select_strategy — all-zero scores fall back to :default" begin
    using Stretto

    device = HeronR3()
    circuit = GateCircuit([GateOp(:H, (1,))], 1)

    zero_strat = Stretto.CompilationStrategy(
        name = :zero_test,
        description = "",
        matches = (c, d) -> 0.0,
    )
    Stretto.register_strategy!(zero_strat)

    selected = Stretto.select_strategy(circuit, device)
    @test selected.name === :default

    Stretto.unregister_strategy!(:zero_test)
end

@testitem ":default strategy registered at module load" begin
    using Stretto

    reg = Stretto.strategies()
    @test haskey(reg, :default)

    default = reg[:default]
    @test default.name === :default
    @test default.description != ""  # non-trivial description
    @test default.matches isa Function

    # Substrate composition: all seam functions should be the exported substrate
    device = HeronR3()
    circuit = GateCircuit([GateOp(:H, (1,))], 1)
    # matches on anything with score 0.0 (not in scoring pool, sentinel)
    @test default.matches(circuit, device) == 0.0
    @test default.post_process == Function[]
end
