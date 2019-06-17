module StanSamples

export read_samples

using ArgCheck: @argcheck
using DocStringExtensions: FIELDS, SIGNATURES, TYPEDEF

####
#### utilities
####

"""
$(SIGNATURES)

Test if the argument is a comment line in Stan sample output.
"""
iscommentline(s::String) = occursin(r"^ *#", s)

"""
$(SIGNATURES)

Return the fields of a line in Stan sample output. The format is CSV,
but never quoted or escaped, so splitting on `,` is sufficient.
"""
fields(line::String) = split(chomp(line), ',')

"""
$(SIGNATURES)

Specification of a variable in the column of the posterior sample.

# Fields

$(FIELDS)
"""
struct ColVar{N}
    "variable name"
    name::Symbol
    "index (may be empty)"
    index::CartesianIndex{N}
end

ColVar(name::Symbol, index::Int...) = ColVar(name, CartesianIndex(tuple(index...)))

"""
$(SIGNATURES)

Test if two `ColVar`s can be merged (same `name` and number of indices).
"""
≅(::ColVar, ::ColVar) = false
≅(v1::ColVar{N}, v2::ColVar{N}) where {N} = v1.name == v2.name

"""
$(SIGNATURES)

Parse a string as a column variable.
"""
function ColVar(s::AbstractString)
    s = split(s, ".")
    name = Symbol(s[1])
    indexes = parse.(Int, s[2:end])
    @argcheck all(indexes .≥ 1) "Non-positive index in $(s)."
    ColVar(name, indexes...)
end

"""
    $(SIGNATURES)

For a vector of indexes, calculate the size (the largest one) and
check that they are contiguous and column-major. Return a tuple of
`Int`s (empty for scalars.)
"""
function combined_size(indexes)
    siz = reduce(max, indexes)
    ran = CartesianIndices(siz)
    # FIXME inelegant collect below
    @argcheck collect(indexes) == vec(collect(ran)) "Non-contiguous indexes."
    siz.I
end

"""
A variable denoting a Stan value, combined from adjacent columns of
with the same variable name. Always has a `name::Symbol`
field. Determines the type of the resulting values.
"""
abstract type StanVar end

"""
$(TYPEDEF)

A scalar (always Float64).
"""
struct StanScalar <: StanVar
    name::Symbol
end

"""
$(TYPEDEF)

An array (always of Float64 elements).
"""
struct StanArray{N} <: StanVar
    name::Symbol
    size::NTuple{N, Int}
end

# this is a shorthand, mainly useful for unit tests
StanArray(name::Symbol, size::Int...) = StanArray(name, size)

"""
$(SIGNATURES)

Type of the value that corresponds to a [`StanVar`](@ref).
"""
valuetype(::StanScalar) = Float64
valuetype(::StanArray{N}) where {N} = Array{Float64, N}

"""
$(SIGNATURES)

Number of columns that correspond to a [`StanVar`](@ref).
"""
ncols(::StanScalar) = 1
ncols(sa::StanArray) = prod(sa.size)

"""
$(SIGNATURES)

Combine column variables into a Stan variable.
"""
function _combine_colvars(colvars)
    var = first(colvars)
    len = findfirst(v -> !(v ≅ var), colvars)
    len = len ≡ nothing ? length(colvars) : len - 1
    siz = combined_size(v.index for v in colvars[1:len])
    if isempty(siz)
        StanScalar(var.name)
    else
        StanArray(var.name, siz)
    end
end

"""
$(SIGNATURES)

Combine column variables, returning a vector of `StanVar`s.
"""
function combine_colvars(colvars)
    header = StanVar[]
    position = 1
    while position ≤ length(colvars)
        v = _combine_colvars(@view colvars[position:end])
        @argcheck v.name ∉ (h.name for h in header) "Duplicate variable $(v.name)."
        position += ncols(v)
        push!(header, v)
    end
    header
end

"""
    _read_values(var, fields)

Read values for `var` from `buffer`, starting at index `1`.
"""
_read_values(var::StanScalar, buffer) = buffer[1]

function _read_values(var::StanArray, buffer)
    a = Array{Float64}(undef, var.size...)
    a[:] .= buffer[1:length(a)]
    a
end

"""
    var_value_dict(vars)

Create an empty dictionary for variable values.
"""
function empty_var_value_dict(vars)
    Dict([var.name => Vector{valuetype(var)}() for var in vars])
end

"""
    read_values(io, vars, var_value_dict)

Read values from a single line of `io` using the variable
specification `vars`.

The fields are combined into variables and appended into the
corresponding vectors in `var_value_dict`.

Return `false` for comment lines, `true` lines with data. All other
cases (ie incomplete lines) throw an error. Note that in this case the
vectors in `var_value_dict` may have an inconsistent length.
"""
function read_values(io, vars, var_value_dict, buffer)
    line = readline(io)
    iscommentline(line) && return false
    buffer .= parse.(Float64, fields(line))
    position = 1
    for var in vars
        a = _read_values(var, @view buffer[position:end])
        push!(var_value_dict[var.name], a)
        position += ncols(var)
    end
    @assert position == length(buffer) + 1 "Fields remaining after parsing."
    true
end

"""
Helper function to read data from a Stan samples CSV file.
"""
function _read_samples(io, vars, var_value_dict, buffer)
    while !eof(io)
        read_values(io, vars, var_value_dict, buffer)
    end
    var_value_dict
end

"""
$(SIGNATURES)

Read Stan samples from a CSV file.
"""
function read_samples(filename)
    open(filename, "r") do io
        while !eof(io)
            line = readline(io)
            if !iscommentline(line)
                colvars = ColVar.(fields(line))
                vars = combine_colvars(colvars)
                var_value_dict = empty_var_value_dict(vars)
                buffer = Vector{Float64}(undef, sum(ncols, vars))
                return _read_samples(io, vars, var_value_dict, buffer)
            end
        end
        error("Could not find non-empty lines.")
    end
end

end # module
