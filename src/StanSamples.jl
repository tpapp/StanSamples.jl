module StanSamples

using ArgCheck
using AutoHashEquals

export read_samples

"""
Test if the argument is a comment line in Stan sample output.
"""
iscommentline(s::String) = ismatch(r"^ *#", s)

"""
Return the fields of a line in Stan sample output. The format is CSV,
but never quoted or escaped, so splitting on `,` is sufficient.
"""
fields(line::String) = split(chomp(line), ',')

"""
Specification of a variable in the column of the posterior sample.

# Fields
- `name` is the name
- `index` is the indices following it (may be empty).
"""
@auto_hash_equals struct ColVar{N}
    name::Symbol
    index::CartesianIndex{N}
end

ColVar(name::Symbol, index::Int...) = ColVar(name, CartesianIndex(tuple(index...)))

"Test if two `ColVar`s can be merged (same `name` and number of indices)."
≅(::ColVar, ::ColVar) = false
≅{N}(v1::ColVar{N}, v2::ColVar{N}) = v1.name == v2.name

"""
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
    combined_size(indexes)

For a vector of indexes, calculate the size (the largest one) and
check that they are contiguous and column-major. Return a tuple of
`Int`s, which is empty for scalars.
"""
function combined_size(indexes)
    siz = reduce(max, indexes)
    ran = CartesianRange(siz)
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
A scalar (always Float64).
"""
struct StanScalar <: StanVar
    name::Symbol
end

"""
An array (always of Float64 elements).
"""
struct StanArray{N} <: StanVar
    name::Symbol
    size::NTuple{N, Int}
end

# this is a shorthand, mainly useful for unit tests
StanArray(name::Symbol, size::Int...) = StanArray(name, size)

"""
Type of the value that corresponds to a `Var`.
"""
valuetype(::StanScalar) = Float64
valuetype{N}(::StanArray{N}) = Array{Float64, N}

"""
Number of columns that correspond to the variable.
"""
ncols(::StanScalar) = 1
ncols(sa::StanArray) = prod(sa.size)

"""
Combine column variables into a Stan variable.

For the documentation of `options`, see [`combine_colvars`](@ref).
"""
function _combine_colvars(colvars; options...)
    var = first(colvars)
    len = findfirst(v -> !(v ≅ var), colvars)
    len = len == 0 ? length(colvars) : len-1
    siz = combined_size(v.index for v in colvars[1:len])
    if isempty(siz)
        StanScalar(var.name)
    else
        StanArray(var.name, siz)
    end
end

"""
    combine_colvars(colvars; options...)

Combine column variables, returning a vector of `StanVar`s.

`options` are not used at the moment.
"""
function combine_colvars(colvars; options...)
    header = StanVar[]
    position = 1
    while position ≤ length(colvars)
        v = _combine_colvars(@view colvars[position:end]; options...)
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
    a = Array{Float64}(var.size...)
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
    read_samples(filename)

Read data from a Stan samples CSV file.

Keyword arguments `options` are used for parsing the variable names,
see [`combine_colvars`](@ref).
"""
function read_samples(filename; options...)
    open(filename, "r") do io
        while !eof(io)
            line = readline(io)
            if !iscommentline(line)
                colvars = ColVar.(fields(line))
                vars = combine_colvars(colvars; options...)
                var_value_dict = empty_var_value_dict(vars)
                buffer = Vector{Float64}(sum(ncols, vars))
                return _read_samples(io, vars, var_value_dict, buffer)
            end
        end
        error("Could not find non-empty lines.")
    end
end

end # module
