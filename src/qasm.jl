# ============================================================================ #
# OpenQASM 3 circuit input  (issue #14)
# ============================================================================ #

"""
    from_qasm(qasm::String) -> GateCircuit

Parse a (static subset of) OpenQASM 3 program into a [`GateCircuit`](@ref).

# Supported
- A single qubit register: `qubit[N] q;` (OpenQASM 3) or `qreg q[N];` (OpenQASM 2 style).
- Non-parametric gates: `id`, `x`, `y`, `z`, `h`, `s`, `sdg`, `t`, `tdg`, `sx`,
  `cx`/`cnot`, `cz`, `swap`, `ccx`/`toffoli`, `ccz`.
- Parametric gates: `rx(θ)`, `ry(θ)`, `rz(θ)`, `p(θ)`/`phase(θ)`/`u1(θ)`,
  `cp(θ)`/`cphase(θ)`, `crz(θ)`, and the general `u(θ, φ, λ)`/`u3(θ, φ, λ)`.
  Angles may be arithmetic expressions over `pi`/`tau`/`euler` and numeric
  literals, e.g. `rx(pi/2)`, `rz(3*pi/4)`, `p(-0.5)`.
- Header lines (`OPENQASM ...`, `include ...`), `//` and `/* */` comments, and
  `barrier` statements, which are ignored.

Qubit indices are converted from OpenQASM's 0-based convention to Stretto's
1-based convention.

# Unsupported (raise `ArgumentError`)
Measurement/reset, classical bits, control flow, custom `gate`/`def` definitions,
and programs declaring more than one qubit register.
"""
function from_qasm(qasm::AbstractString)::GateCircuit
    statements = _qasm_statements(qasm)

    n_qubits = 0
    qreg = nothing
    declared = false
    ops = GateOp[]

    for stmt in statements
        m = match(r"^([A-Za-z_]\w*)", stmt)   # leading keyword/gate name
        head = m === nothing ? "" : m.captures[1]

        if head in ("OPENQASM", "include", "barrier", "gphase")
            continue  # header / no-op for the unitary
        elseif head in ("qubit", "qreg")
            declared && throw(ArgumentError(
                "Multiple qubit registers are not supported (got a second '$stmt')."))
            qreg, n_qubits = _parse_qubit_decl(stmt)
            declared = true
        elseif head in ("bit", "creg", "measure", "reset", "if", "for", "while",
                        "def", "gate", "input", "output", "let")
            throw(ArgumentError("Unsupported OpenQASM construct: '$stmt'."))
        else
            declared || throw(ArgumentError(
                "Gate '$stmt' appears before any qubit register declaration."))
            push!(ops, _parse_gate(stmt, qreg, n_qubits)...)
        end
    end

    declared || throw(ArgumentError("No qubit register declared in the program."))
    return GateCircuit(ops, n_qubits)
end

# --- lexing -----------------------------------------------------------------

function _qasm_statements(qasm::AbstractString)
    s = replace(qasm, r"/\*.*?\*/"s => " ")          # block comments
    s = replace(s, r"//[^\n]*" => " ")               # line comments
    return [strip(p) for p in split(s, ';') if !isempty(strip(p))]
end

function _parse_qubit_decl(stmt::AbstractString)
    # qubit[N] q   |   qubit q   |   qreg q[N]   |   qreg q
    m = match(r"^qubit\s*\[\s*(\d+)\s*\]\s+(\w+)$", stmt)
    m !== nothing && return (m.captures[2], parse(Int, m.captures[1]))
    m = match(r"^qubit\s+(\w+)$", stmt)
    m !== nothing && return (m.captures[1], 1)
    m = match(r"^qreg\s+(\w+)\s*\[\s*(\d+)\s*\]$", stmt)
    m !== nothing && return (m.captures[1], parse(Int, m.captures[2]))
    m = match(r"^qreg\s+(\w+)$", stmt)
    m !== nothing && return (m.captures[1], 1)
    throw(ArgumentError("Could not parse qubit register declaration: '$stmt'."))
end

# --- gate statements --------------------------------------------------------

function _parse_gate(stmt::AbstractString, qreg, n_qubits::Int)
    m = match(r"^(\w+)\s*(?:\(([^)]*)\))?\s+(.+)$", stmt)
    m === nothing && throw(ArgumentError("Could not parse gate statement: '$stmt'."))
    name = lowercase(m.captures[1])
    argstr = m.captures[2]
    qubits = _parse_targets(m.captures[3], qreg, n_qubits)
    angles = argstr === nothing ? Float64[] :
             [_eval_angle(a) for a in split(argstr, ',')]

    sym = _gate_symbol(name, angles)
    return (GateOp(sym, Tuple(qubits)),)
end

function _parse_targets(s::AbstractString, qreg, n_qubits::Int)
    qubits = Int[]
    for tok in split(s, ',')
        t = strip(tok)
        m = match(r"^(\w+)\s*\[\s*(\d+)\s*\]$", t)
        m === nothing && throw(ArgumentError("Could not parse qubit operand: '$t'."))
        qreg !== nothing && m.captures[1] != qreg && throw(ArgumentError(
            "Unknown qubit register '$(m.captures[1])' in '$t'."))
        idx = parse(Int, m.captures[2])           # 0-based
        (0 <= idx < n_qubits) || throw(ArgumentError(
            "Qubit index $idx out of range for a $n_qubits-qubit register."))
        push!(qubits, idx + 1)                     # → 1-based
    end
    return qubits
end

# --- safe angle expression evaluation ---------------------------------------
#
# A small recursive-descent evaluator over the arithmetic grammar
#   expr   := term  (('+'|'-') term)*
#   term   := power (('*'|'/') power)*
#   power  := unary ('^' power)?            # right associative
#   unary  := ('+'|'-')* atom
#   atom   := number | const | '(' expr ')'
# supporting the OpenQASM built-in constants pi/tau/euler. It deliberately
# avoids `eval`, so no OpenQASM input can ever trigger code execution.

const _ANGLE_CONSTS = Dict("pi" => Float64(π), "π" => Float64(π),
                           "tau" => 2Float64(π), "τ" => 2Float64(π),
                           "euler" => Float64(ℯ), "ℯ" => Float64(ℯ))

function _tokenize_angle(expr::AbstractString)
    toks = String[]
    i = firstindex(expr)
    n = lastindex(expr)
    while i <= n
        c = expr[i]
        if isspace(c)
            i = nextind(expr, i)
        elseif c in ('+', '-', '*', '/', '^', '(', ')')
            push!(toks, string(c)); i = nextind(expr, i)
        elseif isdigit(c) || c == '.'
            j = i
            while j <= n && (isdigit(expr[j]) || expr[j] in ('.', 'e', 'E') ||
                  (expr[j] in ('+', '-') && expr[prevind(expr, j)] in ('e', 'E')))
                j = nextind(expr, j)
            end
            push!(toks, expr[i:prevind(expr, j)]); i = j
        elseif isletter(c) || c in ('π', 'τ', 'ℯ')
            j = i
            while j <= n && (isletter(expr[j]) || expr[j] in ('π', 'τ', 'ℯ'))
                j = nextind(expr, j)
            end
            push!(toks, lowercase(expr[i:prevind(expr, j)])); i = j
        else
            throw(ArgumentError("Unexpected character '$c' in angle '$expr'."))
        end
    end
    return toks
end

function _eval_angle(expr::AbstractString)
    toks = _tokenize_angle(expr)
    pos = Ref(1)
    val = _angle_expr(toks, pos, expr)
    pos[] <= length(toks) &&
        throw(ArgumentError("Unexpected token '$(toks[pos[]])' in angle '$expr'."))
    return val
end

_peek(toks, pos) = pos[] <= length(toks) ? toks[pos[]] : nothing

function _angle_expr(toks, pos, expr)
    v = _angle_term(toks, pos, expr)
    while _peek(toks, pos) in ("+", "-")
        op = toks[pos[]]; pos[] += 1
        r = _angle_term(toks, pos, expr)
        v = op == "+" ? v + r : v - r
    end
    return v
end

function _angle_term(toks, pos, expr)
    v = _angle_power(toks, pos, expr)
    while _peek(toks, pos) in ("*", "/")
        op = toks[pos[]]; pos[] += 1
        r = _angle_power(toks, pos, expr)
        v = op == "*" ? v * r : v / r
    end
    return v
end

function _angle_power(toks, pos, expr)
    v = _angle_unary(toks, pos, expr)
    if _peek(toks, pos) == "^"
        pos[] += 1
        v = v ^ _angle_power(toks, pos, expr)   # right associative
    end
    return v
end

function _angle_unary(toks, pos, expr)
    if _peek(toks, pos) == "-"
        pos[] += 1; return -_angle_unary(toks, pos, expr)
    elseif _peek(toks, pos) == "+"
        pos[] += 1; return _angle_unary(toks, pos, expr)
    end
    return _angle_atom(toks, pos, expr)
end

function _angle_atom(toks, pos, expr)
    tok = _peek(toks, pos)
    tok === nothing && throw(ArgumentError("Incomplete angle expression '$expr'."))
    if tok == "("
        pos[] += 1
        v = _angle_expr(toks, pos, expr)
        _peek(toks, pos) == ")" || throw(ArgumentError("Unbalanced parentheses in '$expr'."))
        pos[] += 1
        return v
    elseif haskey(_ANGLE_CONSTS, tok)
        pos[] += 1; return _ANGLE_CONSTS[tok]
    else
        v = tryparse(Float64, tok)
        v === nothing && throw(ArgumentError("Invalid token '$tok' in angle '$expr'."))
        pos[] += 1; return v
    end
end

# --- gate name → Stretto symbol ---------------------------------------------

# names that resolve directly through GATES / EXTRA_GATES
const _QASM_FIXED = Dict{String,Symbol}(
    "x" => :X, "y" => :Y, "z" => :Z, "h" => :H,
    "s" => :S, "t" => :T, "sx" => :SX,
    "cx" => :CX, "cnot" => :CX, "cz" => :CZ,
    "ccx" => :CCX, "toffoli" => :CCX, "ccz" => :CCZ,
)

function _register!(sym::Symbol, mat::AbstractMatrix)
    haskey(EXTRA_GATES, sym) || (EXTRA_GATES[sym] = Matrix{ComplexF64}(mat))
    return sym
end

function _gate_symbol(name::String, angles::Vector{Float64})
    # parametric gates: build the matrix and register a unique symbol
    if !isempty(angles)
        θ = angles[1]
        if name == "rx"
            return _register!(Symbol("RX($θ)"), _rx(θ))
        elseif name == "ry"
            return _register!(Symbol("RY($θ)"), _ry(θ))
        elseif name == "rz"
            return _register!(Symbol("RZ($θ)"), _rz(θ))
        elseif name in ("p", "phase", "u1")
            return _register!(Symbol("P($θ)"), _p(θ))
        elseif name in ("cp", "cphase", "cu1")
            return _register!(Symbol("CP($θ)"), cp_gate(θ))
        elseif name == "crz"
            return _register!(Symbol("CRZ($θ)"), _crz(θ))
        elseif name in ("u", "u3")
            length(angles) == 3 || throw(ArgumentError("$name expects 3 angles."))
            return _register!(Symbol("U($(angles[1]),$(angles[2]),$(angles[3]))"),
                              _u(angles...))
        end
        throw(ArgumentError("Unsupported parametric gate '$name'."))
    end

    # fixed gates
    haskey(_QASM_FIXED, name) && return _QASM_FIXED[name]
    name == "id" && return _register!(:Id, ComplexF64[1 0; 0 1])
    name == "sdg" && return _register!(:Sdg, ComplexF64[1 0; 0 -im])
    name == "tdg" && return _register!(:Tdg, ComplexF64[1 0; 0 exp(-im*π/4)])
    name == "swap" && return _register!(:SWAP,
        ComplexF64[1 0 0 0; 0 0 1 0; 0 1 0 0; 0 0 0 1])

    throw(ArgumentError("Unsupported gate '$name'."))
end

# --- parametric gate matrices -----------------------------------------------

_rx(θ) = ComplexF64[cos(θ/2) -im*sin(θ/2); -im*sin(θ/2) cos(θ/2)]
_ry(θ) = ComplexF64[cos(θ/2) -sin(θ/2); sin(θ/2) cos(θ/2)]
_rz(θ) = ComplexF64[exp(-im*θ/2) 0; 0 exp(im*θ/2)]
_p(θ)  = ComplexF64[1 0; 0 exp(im*θ)]
_crz(θ) = ComplexF64[1 0 0 0; 0 1 0 0; 0 0 exp(-im*θ/2) 0; 0 0 0 exp(im*θ/2)]
function _u(θ, φ, λ)
    return ComplexF64[
        cos(θ/2)            -exp(im*λ)*sin(θ/2);
        exp(im*φ)*sin(θ/2)  exp(im*(φ+λ))*cos(θ/2)
    ]
end

# ============================================================================ #
# Tests
# ============================================================================ #

@testitem "from_qasm — qubit count and 0→1 based indices" begin
    using Stretto
    c = from_qasm("qubit[3] q; x q[0]; x q[2];")
    @test c.n_qubits == 3
    @test [op.qubits for op in c.ops] == [(1,), (3,)]
    @test from_qasm("qreg q[2]; h q[0];").n_qubits == 2   # OpenQASM 2 style
end

@testitem "from_qasm — discrete gates round-trip via circuit_unitary" begin
    using Stretto
    qasm = """
    OPENQASM 3.0;
    include "stdgates.inc";
    qubit[2] q;
    h q[0];
    cx q[0], q[1];
    """
    expected = circuit_unitary(GateCircuit([GateOp(:H, (1,)), GateOp(:CX, (1, 2))], 2))
    @test circuit_unitary(from_qasm(qasm)) ≈ expected atol=1e-12
end

@testitem "from_qasm — Toffoli (ccx)" begin
    using Stretto
    U = circuit_unitary(from_qasm("qubit[3] q; ccx q[0], q[1], q[2];"))
    @test U ≈ circuit_unitary(toffoli_circuit()) atol=1e-12
end

@testitem "from_qasm — parametric rx/ry/rz match their definitions" begin
    using Stretto
    using LinearAlgebra
    rx = circuit_unitary(from_qasm("qubit[1] q; rx(pi/2) q[0];"))
    @test rx ≈ [cos(π/4) -im*sin(π/4); -im*sin(π/4) cos(π/4)] atol=1e-12

    rz = circuit_unitary(from_qasm("qubit[1] q; rz(pi/3) q[0];"))
    @test rz ≈ [exp(-im*π/6) 0; 0 exp(im*π/6)] atol=1e-12

    # phase gate p(θ) and a half-turn rz are diagonal
    p = circuit_unitary(from_qasm("qubit[1] q; p(0.7) q[0];"))
    @test p ≈ [1 0; 0 exp(im*0.7)] atol=1e-12
end

@testitem "from_qasm — angle expressions (pi, tau, arithmetic)" begin
    using Stretto
    a = circuit_unitary(from_qasm("qubit[1] q; rz(3*pi/4) q[0];"))
    b = circuit_unitary(from_qasm("qubit[1] q; rz(-pi/2 + 5*pi/4) q[0];"))  # = 3π/4
    @test a ≈ b atol=1e-12
    @test circuit_unitary(from_qasm("qubit[1] q; rz(tau) q[0];")) ≈
          circuit_unitary(from_qasm("qubit[1] q; rz(2*pi) q[0];")) atol=1e-12
end

@testitem "from_qasm — parametric two-qubit cp matches the native QFT primitive" begin
    using Stretto
    # cp(θ) on (q0,q1) must equal Stretto's own controlled-phase used in qft_circuit
    U = circuit_unitary(from_qasm("qubit[2] q; cp(pi/2) q[0], q[1];"))
    expected = [1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 exp(im*π/2)]
    @test U ≈ expected atol=1e-12
end

@testitem "from_qasm — comments and barriers are ignored" begin
    using Stretto
    qasm = """
    qubit[1] q;
    // a line comment
    h q[0];  /* inline block */ barrier q[0];
    """
    @test circuit_unitary(from_qasm(qasm)) ≈ (1/√2) * [1 1; 1 -1] atol=1e-12
end

@testitem "from_qasm — unsupported constructs raise" begin
    using Stretto
    @test_throws ArgumentError from_qasm("qubit[1] q; measure q[0];")
    @test_throws ArgumentError from_qasm("qubit[1] q; foo q[0];")
    @test_throws ArgumentError from_qasm("qubit[1] q; x q[5];")        # out of range
    @test_throws ArgumentError from_qasm("qubit[1] a; qubit[1] b; x a[0];")  # 2 registers
    @test_throws ArgumentError from_qasm("h q[0];")                   # no declaration
end
