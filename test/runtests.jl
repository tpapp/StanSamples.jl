using StanSamples
import StanSamples:
    iscommentline,
    fields,
    ScalarVar,
    IndexedVar,
    parse_varname,
    combined_size,
    parse_header
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
    @test parse_varname("a") == ScalarVar(:a)
    @test parse_varname("b99") == ScalarVar(:b99)
    @test parse_varname("accept_stat__") == ScalarVar(:accept_stat__)
    @test parse_varname("a.1.2.3") == IndexedVar(:a, 1, 2, 3)
    @test_throws ArgumentError parse_varname("a.foo")
    @test_throws ArgumentError parse_varname("a.0")
    @test_throws ArgumentError parse_varname("a.0.")
end

@testset "combined size" begin
    @test combined_size([CartesianIndex((i,)) for i in 1:3]) == CartesianIndex((3,))
    @test combined_size(vec([CartesianIndex((i,j)) for i in 1:3, j in 1:4])) ==
        CartesianIndex((3,4))
    @test_throws ArgumentError combined_size([CartesianIndex((i,)) for i in [1,3]])
    @test_throws ArgumentError combined_size([CartesianIndex((i,)) for i in [2,1]])
end

@testset "parsing header" begin
    let h = ScalarVar.([:a, :b, :c])
        @test parse_header(h) == h
    end
    @test parse_header(parse_varname.(["a", "b.1", "b.2", "c"])) ==
        [ScalarVar(:a), IndexedVar(:b, 2), ScalarVar(:c)]
    @test parse_header(parse_varname.(["a", "b.1.1", "b.2.1", "b.1.2", "b.2.2", "c"])) ==
        [ScalarVar(:a), IndexedVar(:b, 2, 2), ScalarVar(:c)]
end
