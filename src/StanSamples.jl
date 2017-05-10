module StanSamples

using ArgCheck
using AutoHashEquals

iscommentline(s::String) = ismatch(r"^ *#", s)

fields(s::String) = split(s, ',')

abstract type HeaderVar end

@auto_hash_equals struct ScalarVar <: HeaderVar
    name::Symbol
end

@auto_hash_equals struct IndexedVar{N} <: HeaderVar
    name::Symbol
    index::CartesianIndex{N}
end

IndexedVar(name::Symbol, index::Int...) = IndexedVar(name, CartesianIndex(tuple(index...)))

function parse_varname(s::String)
    s = split(s, ".")
    name = Symbol(s[1])
    if length(s) > 1
        indexes = parse.(Int, s[2:end])
        @argcheck all(indexes .≥ 1) "Non-positive index in $(s)."
        IndexedVar(name, indexes...)
    else
        ScalarVar(name)
    end
end

combine_vars(vars) = _combine_vars(vars[1], vars)

_combine_vars(var::ScalarVar, vars) = var, 1

function combined_size(indexes)
    siz = reduce(max, indexes)
    ran = CartesianRange(siz)
    # FIXME inelegant collect below
    @argcheck collect(indexes) == vec(collect(ran)) "Non-contiguous indexes."
    siz
end

function _combine_vars{N}(var::IndexedVar{N}, vars)
    name = var.name
    len = findfirst(v -> v.name != name, vars)
    len = len == 0 ? length(vars) : len-1
    IndexedVar(name, combined_size(v.index for v in vars[1:len])), len
end

function parse_header(vars)
    header = HeaderVar[]
    position = 1
    while position ≤ length(vars)
        v, len = combine_vars(@view vars[position:end])
        @argcheck v.name ∉ (h.name for h in header) "Duplicate variable $(v.name)."
        position += len
        push!(header, v)
    end
    header
end

end # module
