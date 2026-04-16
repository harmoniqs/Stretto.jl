using Test
using Stretto

@testset "Stretto.jl" begin
    include("test_devices.jl")
    include("test_circuits.jl")
end
