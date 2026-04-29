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
