module StanSamples

using ArgCheck
using AutoHashEquals

iscommentline(s::String) = ismatch(r"^ *#", s)

fields(s::String) = split(s, ',')

"""
A variable in the posterior sample. `name` is the name, and `index` is
the indices following it. When combined after parsing the header,
`index` is the size of the array that is to be read.
"""
@auto_hash_equals struct Var{N}
    name::Symbol
    index::CartesianIndex{N}
end

Var(name::Symbol, index::Int...) = Var(name, CartesianIndex(tuple(index...)))

"Test if two `Var`s can be merged (same name and number of indices)."
≅(::Var, ::Var) = false

≅{N}(v1::Var{N}, v2::Var{N}) = v1.name == v2.name


function parse_varname(s::String)
    s = split(s, ".")
    name = Symbol(s[1])
    indexes = parse.(Int, s[2:end])
    @argcheck all(indexes .≥ 1) "Non-positive index in $(s)."
    Var(name, indexes...)
end

function combined_size(indexes)
    siz = reduce(max, indexes)
    ran = CartesianRange(siz)
    # FIXME inelegant collect below
    @argcheck collect(indexes) == vec(collect(ran)) "Non-contiguous indexes."
    siz
end

function _combine_vars(vars)
    var = first(vars)
    len = findfirst(v -> !(v ≅ var), vars)
    len = len == 0 ? length(vars) : len-1
    Var(var.name, combined_size(v.index for v in vars[1:len])), len
end

function combine_vars(vars)
    header = Var[]
    position = 1
    while position ≤ length(vars)
        v, len = _combine_vars(@view vars[position:end])
        @argcheck v.name ∉ (h.name for h in header) "Duplicate variable $(v.name)."
        position += len
        push!(header, v)
    end
    header
end

end # module
