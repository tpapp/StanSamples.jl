using StanSamples
import StanSamples:
    iscommentline,
    fields,
    ColVar,
    combined_size,
    StanVar,
    StanScalar,
    StanArray,
    combine_colvars,
    valuetype,
    ncols,
    empty_var_value_dict,
    _read_values,
    read_values
using Base.Test

@testset "raw reading" begin
    @test iscommentline("# this is a comment")
    @test iscommentline(" # this is a comment")
    @test iscommentline("#")
    @test !iscommentline("fly in the ointment #")
    @test !iscommentline("99,12")
    @test !iscommentline("99,12#comment")
    @test fields("a,b,c") == ["a","b","c"]
    @test fields("") == [""] # corner cases, should not appear in a CSV produced by CmdStan
    @test fields(",") == ["",""]
end

@testset "parsing variable names" begin
    @test ColVar("a") == ColVar(:a)
    @test ColVar("b99") == ColVar(:b99)
    @test ColVar("accept_stat__") == ColVar(:accept_stat__)
    @test ColVar("a.1.2.3") == ColVar(:a, 1, 2, 3)
    @test_throws ArgumentError ColVar("a.foo")
    @test_throws ArgumentError ColVar("a.0")
    @test_throws ArgumentError ColVar("a.0.")
end

@testset "combined size" begin
    @test combined_size([CartesianIndex((i,)) for i in 1:3]) == (3,)
    @test combined_size(vec([CartesianIndex((i,j))
                             for i in 1:3, j in 1:4])) == (3,4)
    @test_throws ArgumentError combined_size([CartesianIndex((i,)) for i in [1,3]])
    @test_throws ArgumentError combined_size([CartesianIndex((i,)) for i in [2,1]])
end

@testset "parsing header" begin
    let h = ColVar.([:a, :b, :c])
        @test combine_colvars(h) == [StanScalar(s) for s in [:a, :b, :c]]
    end
    @test combine_colvars(ColVar.(["a", "b.1", "b.2", "c"])) ==
        [StanScalar(:a), StanArray(:b, (2,)), StanScalar(:c)]
    @test combine_colvars(ColVar.(["a", "b.1.1", "b.2.1", "b.1.2", "b.2.2", "c"])) ==
        [StanScalar(:a), StanArray(:b, (2, 2)), StanScalar(:c)]
    @test_throws ArgumentError combine_colvars(ColVar.(["a", "b.1", "b.2.1", "c"]))
end

@testset "variable types" begin
    a = StanScalar(:A)
    b, c, d = [StanArray(arg...) for arg in [(:B,2), (:C,2,3), (:D,2,3,5)]]
    @test valuetype(a) == Float64
    @test ncols(a) == 1
    @test valuetype(b) == Vector{Float64}
    @test ncols(b) == 2
    @test valuetype(c) == Matrix{Float64}
    @test ncols(c) == 6
    @test valuetype(d) == Array{Float64, 3}
    @test ncols(d) == 30
end

@testset "empty var dictionary" begin
    vars = [StanScalar(:A), StanArray(:B,1), StanArray(:C,1,2), StanArray(:D,1,2,3)]
    @test empty_var_value_dict(vars) == Dict(:A => Vector{Float64}(0),
                                             :B => Vector{Vector{Float64}}(0),
                                             :C => Vector{Matrix{Float64}}(0),
                                             :D => Vector{Array{Float64, 3}}(0))
end

@testset "_read_values" begin
    @test _read_values(StanScalar(:a), [1.0]) == 1.0
    @test _read_values(StanArray(:a,2), [1.0, 2.0]) == [1.0, 2.0]
    @test _read_values(StanArray(:a,2,2), 1.0:4.0) == [1.0 3.0; 2.0 4.0]
    @test_throws BoundsError _read_values(StanArray(:a, 9), 1.0:4.0)
end

@testset "read values" begin
    # line with values
    io = IOBuffer("""
1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0
  # next line is too long, one after that is incomplete, then unparsable
1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0
1.0,2.0,3.0,4.0,5.0,6.0,7.0
1.0,foo,3.0,4.0,5.0,6.0,7.0,8.0
""")
    vars = [StanScalar(:a), StanArray(:b, 3), StanArray(:c, 2, 2)]
    @test sum(ncols.(vars)) == 8
    vars_values = empty_var_value_dict(vars)
    buffer = Vector{Float64}(sum(ncols.(vars)))
    @test read_values(io, vars, vars_values, buffer)
    @test vars_values == Dict(:a => [1.0], :b => [[2.0, 3.0, 4.0]],
                              :c => [[5.0 7.0; 6.0 8.0]])
    # comment line
    @test !read_values(io, vars, vars_values, buffer)
    # line too long
    @test_throws DimensionMismatch read_values(io, vars, vars_values, buffer)
    # incomplete line
    @test_throws DimensionMismatch read_values(io, vars, vars_values, buffer)
    # parser error
    @test_throws ArgumentError read_values(io, vars, vars_values, buffer)
end

@testset "read samples" begin
    samples = read_samples(Pkg.dir("StanSamples", "test", "testmodel", "test-samples-1.csv"))
    scalar_vars = [:lp__,:accept_stat__,:stepsize__,:treedepth__,:n_leapfrog__,
                   :divergent__,:energy__,:mu,:sigma, :nu]
    @test Set(keys(samples)) == Set(vcat(scalar_vars, :alpha))
    N = 1000                    # hardcoded
    for v in scalar_vars
        @test isa(samples[v], Vector{Float64})
        @test length(samples[v]) == N
    end
    α = samples[:alpha]
    @test isa(α, Vector{Matrix{Float64}})
    @test length(α) == N
    @test all(size(a) == (3,5) for a in α)
end
