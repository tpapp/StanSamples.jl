# StanSamples.jl

![lifecycle](https://img.shields.io/badge/lifecycle-maturing-blue.svg)
[![build](https://github.com/tpapp/StanSamples.jl/workflows/CI/badge.svg)](https://github.com/tpapp/StanSamples.jl/actions?query=workflow%3ACI)
[![codecov.io](http://codecov.io/github/tpapp/StanSamples.jl/coverage.svg?branch=master)](http://codecov.io/github/tpapp/StanSamples.jl?branch=master)

Read Stan samples from a CSV file. Columns that belong to the same variable are grouped into arrays.

```julia
julia> using StanSamples

julia> DATA = "a,b.1,b.2,c.1.1,c.2.1,c.1.2,c.2.2\n" *
              "1.0,2.0,3.0,4.0,5.0,6.0,7.0\n" *
              "8.0,9.0,10.0,11.0,12.0,13.0,14.0"

julia> samples = read_samples(IOBuffer(DATA));

julia> samples.a
2-element Array{Float64,1}:
 1.0
 8.0

julia> samples.b
2×2 ElasticArrays.ElasticArray{Float64,2,1}:
 2.0   9.0
 3.0  10.0

julia> samples.c
2×2×2 ElasticArrays.ElasticArray{Float64,3,2}:
[:, :, 1] =
 4.0  6.0
 5.0  7.0

[:, :, 2] =
 11.0  13.0
 12.0  14.0

julia> header, matrix = read_sample_matrix(IOBuffer(DATA))

julia> header, matrix = read_sample_matrix(io);

julia> header
7-element Vector{SubString{String}}:
 "a"
 "b.1"
 "b.2"
 "c.1.1"
 "c.2.1"
 "c.1.2"
 "c.2.2"

julia> matrix
2×7 Matrix{Float64}:
 1.0  2.0   3.0   4.0   5.0   6.0   7.0
 8.0  9.0  10.0  11.0  12.0  13.0  14.0
```
