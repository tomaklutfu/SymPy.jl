## Alternate constructors for symbolic objects
##
## Many (too many) ways to create symbolobjects
## Sym("x"), Sym(:x), Sym("x", "y") or Sym(:x, :y), @syms x y, symbols("x y")

"Create a symbolic object from a symbol or string"
Sym(s::Union(Symbol, String)) = sympy.symbols(string(s))

"Create a symbolic number"
Sym(s::Rational) = convert(Sym, s)
Sym{T <: Number}(s::T) = sympy.sympify(s)


"vectorized version of `Sym`"
Sym(args...) = map(Sym, args)

## (a,b,c) = @syms a b c --- no commas on right hand side!
## (x,) @syms x is needed for single arguments
## Thanks to vtjnash for this!
"""

Macro to create many symbolic objects at once. (Written by `@vtjnash`.)

Example: `a,b,c = @syms a b c`

"""
macro syms(x...)
    q=Expr(:block)
    if length(x) == 1 && isa(x[1],Expr)
        @assert x[1].head === :tuple "@syms expected a list of symbols"
        x = x[1].args
    end 
    for s in x
        @assert isa(s,Symbol) "@syms expected a list of symbols"
        push!(q.args, Expr(:(=), s, Expr(:call, :Sym, Expr(:quote, s))))
           end 
    push!(q.args, Expr(:tuple, x...))
    q   
end

"Macro to create a symbolic object: `sym\"x\"`"
macro sym_str(x)
    Sym(x)
end

## define one or more symbols directly
## a,b,c = symbols("a,b,c", commutative=false)
"""

Function to create one or more symbolic objects. These are specified with a string,
with commas separating different variables.

This function allows the passing of assumptions about the variables
such as `positive=true`, `real=true` or `commutative=true`.

Example:

```
x,y,z = symbols("x, y, z", real=true)
```

"""
function symbols(x::String; kwargs...) 
    out = sympy.symbols(x; kwargs...)
end


length(x::SymbolicObject) = *(size(x)...)
function size(x::SymbolicObject)
    return ()
end
function size(x::SymbolicObject, dim::Integer)
    if dim <= 0
        error("dimension out of range")
   
    else
        return 1
    end
end

## pull out x property of Sym objects or leave alone
project(x::Any) = x
project(x::SymbolicObject) = x.x
project(x::Symbol) = project(Sym(x)) # can use :x instead of Sym(x)
project(x::Tuple) = map(project, x)


## Iterator for Sym
Base.start(x::Sym) = 1
Base.next(x::Sym, state) = (x.x, state-1)
Base.done(x::Sym, state) = state <= 0






"""
convert args so that we can use obj[:methname](x,...) without needing to project to
python: obj.method(arg1, arg2, ...) -> julia: obj[:meth](args...) 

Examples:
```
x = Sym("x")
(x^2 - 2x + 1)[:diff]()
(x^2 - 2x + 1)[:integrate]((x,0,1))
```

"""
function getindex(x::SymbolicObject, i::Symbol)
    ## find method
    if haskey(project(x), i)
        out = project(x)[i]
        if isa(out, Function) 
            function f(args...;kwargs...) 
                out(project(args)...;kwargs...)
            end
            return f
        else
            return out
        end
    elseif i in names(sympy)
        out = sympy.(i)
        if isa(out, Function) 
            function f(args...;kwargs...) 
                out(project(x), project(args)...;kwargs...) 
            end
            return f
        else
            return out
        end
    else
        MethodError()
    end
end


## Various means to call sympy or object methods. All convert input,
## not all convert output.
##
## we may have sympy.method
## or we may have object.method

## Makes it possible to call in a sympy method, witout worrying about Sym objects
call_sympy_fun(fn::Function, args...; kwargs...) = fn(map(project, args)...; [(k,project(v)) for (k,v) in kwargs]...)
function sympy_meth(meth::Symbol, args...; kwargs...) 
    ans = call_sympy_fun(getfield(sympy,meth), args...; kwargs...)
    ## make nicer...
    if isa(ans, Vector)
        ans = Sym[i for i in ans]
    end
    ans
end
        

## meth of object, convert arguments
object_meth(object::SymbolicObject, meth::Symbol, args...; kwargs...) =  
  call_sympy_fun(project(object)[meth],  args...; kwargs...)


## meth of object, convert arguments, output to SymMatrix 
function call_matrix_meth(object::SymbolicObject, meth::Symbol, args...; kwargs...) 
    out = object_meth(object, meth, args...; kwargs...)
    if isa(out, SymMatrix) 
        convert(Array{Sym}, out)
    elseif  length(out) == 1
        out 
    else
        map(u -> isa(u, SymMatrix) ? convert(Array{Sym}, u) : u, out)
    end
end



## From PyCall.pywrap:
function members(o::Union(PyObject, Sym))
    out = convert(Vector{(String,PyObject)}, 
                  pycall(PyCall.inspect["getmembers"], PyObject, project(o)))
    String[u[1] for u in out]
end

