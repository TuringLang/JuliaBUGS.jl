module Parser

using MacroTools
using JuliaSyntax
using JuliaSyntax: @K_str, @KSet_str, tokenize, untokenize, Diagnostic, Token

include("utils.jl")
include("bugs_parser.jl")
include("whitelist.jl")
include("bugs_macro.jl")

"""
    to_julia_program

Convert a BUGS program to a Julia program.

# Arguments
- `prog::String`: A string containing the BUGS program that needs to be converted.
- `replace_period::Bool=true`: A flag to determine whether periods should be replaced in the 
conversion process. If `true`, periods in variable names or other relevant places will be 
replaced with an underscore. If `false`, periods will be retained, and variable name will be
wrapped in `var"..."` to avoid syntax error.
- `no_enclosure::Bool=false`: A flag to determine the enclosure processing strategy. 
If `true`, the parse will not enforce the requirement that the program body to be enclosed in
"model { ... }". 

"""
function to_julia_program(prog::String, replace_period=true, no_enclosure=false)
    ps = ProcessState(prog, replace_period)
    if no_enclosure
        process_toplevel_no_enclosure!(ps)
    else
        process_toplevel!(ps)
    end
    isempty(ps.diagnostics) || giveup!(ps)
    return to_julia_program(ps.julia_token_vec, ps.text)
end

export @bugs, to_julia_program

end
