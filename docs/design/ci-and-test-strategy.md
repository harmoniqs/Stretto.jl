# CI and Test Strategy

**Status:** design note, not yet implemented
**Scope:** v0.1 → v0.2 transition

## Motivation

Stretto compiles whole circuits to single pulses, which means it routinely
builds Piccolo problems at dimensions (81-dim, 8 drives, 20+ knots) where
Piccolo's default `BilinearIntegrator` is unusable — evaluator construction
alone exhausted 62GB of RAM for QFT-4 on this hardware. Piccolissimo's
`SplineIntegrator` handles these problems in seconds.

Piccolissimo is private. Contributors without access to the repo must still
be able to clone Stretto, run tests, and develop features on small problems.

## Layered test tags

All `@testitem` blocks in `src/**/*.jl` carry tags that cross two axes:

| Axis | Tag | Meaning |
|---|---|---|
| Backend | `:piccolo` (default, no tag) | Runs with Piccolo alone |
| Backend | `:piccolissimo` | Requires Piccolissimo to be loaded (or the extension to be active) |
| Weight | `:integration` | Takes more than ~30 seconds regardless of backend |

`runtests.jl` chooses the filter:

```julia
# Default filter (cloner without Piccolissimo):
@run_package_tests filter = ti -> !(:piccolissimo in ti.tags) && !(:integration in ti.tags)

# Full CI filter (has Piccolissimo):
@run_package_tests filter = ti -> true
```

A `@testitem` that needs a big solve is tagged both `:piccolissimo` and
`:integration`. A `@testitem` that exercises the pipeline on a toy 2Q
problem but still calls Ipopt is tagged `:integration` only (runs on either
backend when the integration suite is opted into).

## Package extension

Stretto declares Piccolissimo as a **weak dependency** (Julia 1.9+ package
extensions). Pattern:

```toml
# Stretto.jl/Project.toml
[weakdeps]
Piccolissimo = "<uuid>"

[extensions]
StrettoPiccolissimoExt = ["Piccolissimo"]
```

`ext/StrettoPiccolissimoExt.jl` defines the fast path:

```julia
module StrettoPiccolissimoExt
using Stretto
using Piccolissimo: SplineIntegrator

# Override Stretto's integrator factory when Piccolissimo is loaded
Stretto.default_integrator() = SplineIntegrator()
end
```

Without Piccolissimo loaded, `Stretto.default_integrator()` returns
Piccolo's `BilinearIntegrator` — fine for 2Q unit tests, inadequate for 4Q.

## CI / GitHub Actions

Stretto's CI needs read access to the private Piccolissimo repo. Chosen
mechanism: a **machine-user PAT** stored as a repository secret.

### One-time setup

1. Create a Harmoniqs machine-user GitHub account (e.g., `harmoniqs-ci`).
2. Grant read access to `Harmoniqs/Piccolissimo.jl` (and other private
   monorepo packages going forward — Altissimo, etc.).
3. Generate a fine-grained PAT with `Contents: Read` on those repos.
4. Add to each downstream repo's Actions secrets as `HARMONIQS_CI_TOKEN`.

### Workflow snippet

```yaml
# .github/workflows/CI.yml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: julia-actions/setup-julia@v2
        with:
          version: '1.10'
      - name: Configure private-repo access
        run: |
          git config --global url."https://x-access-token:${{ secrets.HARMONIQS_CI_TOKEN }}@github.com/".insteadOf "https://github.com/"
      - uses: julia-actions/cache@v2
      - uses: julia-actions/julia-buildpkg@v1
      - uses: julia-actions/julia-runtest@v1
```

The `insteadOf` rewrite is what makes `Pkg.add("Piccolissimo")` resolve
against the private repo without the Julia side knowing anything about
authentication.

### Test matrix

Two jobs:

- `test-piccolo`: no Piccolissimo in the env. Runs `@run_package_tests
  filter = ti -> !(:piccolissimo in ti.tags) && !(:integration in
  ti.tags)`. Must pass for every PR.
- `test-piccolissimo`: adds Piccolissimo to the test env. Runs the full
  suite including `:piccolissimo` and `:integration`. Required on main,
  optional on PR (to keep PR feedback fast).

## Tradeoffs

- External contributors without PAT access can reproduce only the
  `:piccolo` suite. Acceptable while Harmoniqs is closed-source. When we
  onboard externally (interns, collaborators), we either (a) open-source
  Piccolissimo, or (b) wire the PAT into a Codespaces or devcontainer
  config.
- The extension mechanism leaks the integrator choice into Stretto's
  public-ish surface (`default_integrator`). Users who want to override
  this manually can do so without loading Piccolissimo — it's just a
  function to overload.
- `:integration` and `:piccolissimo` tags are orthogonal, which means
  four quadrants. Only three of the four matter in practice (tiny tests
  that need Piccolissimo are rare); we document as we go.

## Future work

- Migrate the v0.1 QFT-4 milestone script to a `:piccolissimo +
  :integration` `@testitem` once the extension is live.
- Add a Harmoniqs-internal Julia registry (`JuliaRegistries/General`-style
  LocalRegistry) so dep resolution doesn't depend on Git URL rewrites.
  This removes the PAT-in-CI friction and makes external installs trivial
  if/when Piccolissimo goes public.
