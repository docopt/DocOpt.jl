__precompile__()

module DocOpt

export docopt

using Printf, Dates

# port of str.partition in Python
function partition(s::AbstractString, delim::AbstractString)
    range = findfirst(delim, s)
    if range == nothing
        # no match
        return s, "", ""
    elseif length(range) == 1
        # delim is a single character
        return s[1:range[1]-1], delim, s[range[1]+1:end]
    else
        start, stop = range
        return s[1:start-1], delim, s[stop+1:end]
    end
end

partition(s::AbstractString, delim::Char) = partition(s::AbstractString, string(delim))

struct DocOptLanguageError <: Exception
    msg::AbstractString
end

struct DocOptExit <: Exception
    usage::AbstractString
end

abstract type Pattern end
abstract type LeafPattern <: Pattern end
abstract type BranchPattern <: Pattern end

mutable struct Argument <: LeafPattern
    name
    value
    Argument(name, value=nothing) = new(name, value)
end

mutable struct Command <: LeafPattern
    name
    value
    Command(name, value=false) = new(name, value)
end

mutable struct Option <: LeafPattern
    short
    long
    argcount::Int
    value

    function Option(short=nothing, long=nothing, argcount=0, value=false)
        value = value === false && argcount > 0 ? nothing : value
        new(short, long, argcount, value)
    end

    function Option(option_description::AbstractString)
        short, long, argcount, value = nothing, nothing, 0, false
        options, _, description = partition(strip(option_description), "  ")
        options = replace(options, ',' => ' ')
        options = replace(options, '=' => ' ')
        for s in split(options)
            if startswith(s, "--")
                long = s
            elseif startswith(s, '-')
                short = s
            else
                argcount = 1
            end
        end
        if argcount > 0
            matched = match(r"\[default: (.*)\]"i, description)
            value = matched == nothing ? nothing : matched.captures[1]
        end
        new(short, long, argcount, value)
    end
end

const Children = Vector{Pattern}

mutable struct Required <: BranchPattern
    children::Children
end

mutable struct Optional <: BranchPattern
    children::Children
end

mutable struct OptionsShortcut <: BranchPattern
    children::Children
    OptionsShortcut() = new(Array[])
end

mutable struct OneOrMore <: BranchPattern
    children::Children
end

mutable struct Either <: BranchPattern
    children::Children
end

mutable struct Tokens
    tokens::Vector{String}
    error::DataType
    function Tokens(source::Array, error=DocOptExit)
        new(source, error)
    end
    function Tokens(source::AbstractString, error=DocOptLanguageError)
        source = replace(source, r"([\[\]\(\)\|]|\.\.\.)" => s -> " " * s * " ")
        source = collect((m.match for m in eachmatch(r"\S*<.*?>|\S+", source)))
        new(source, error)
    end
end

function IteratorSize(::Type{Tokens})
    return Base.SizeUnknown()
end

name(pattern::LeafPattern) = pattern.name
name(o::Option) = o.long !== nothing ? o.long : o.short

function single_match(pattern::Command, left)
    for (n, pat) in enumerate(left)
        if isa(pat, Argument)
            if pat.value == name(pattern)
                return n, Command(name(pattern), true)
            else
                break
            end
        end
    end
    return nothing, nothing
end

function single_match(pattern::Argument, left)
    for (n, pat) in enumerate(left)
        if isa(pat, Argument)
            return n, Argument(name(pattern), pat.value)
        end
    end
    return nothing, nothing
end

function single_match(pattern::Option, left)
    for (n, pat) in enumerate(left)
        if name(pattern) == name(pat)
            return n, pat
        end
    end
    return nothing, nothing
end

Base.:(==)(x::Argument, y::Argument) = x.name == y.name && x.value == y.value
Base.:(==)(x::Command, y::Command) = x.name == y.name && x.value == y.value
Base.:(==)(x::Option, y::Option) = x.short == y.short && x.long == y.long && x.argcount == y.argcount && x.value == y.value
Base.:(==)(x::BranchPattern, y::BranchPattern) = x.children == y.children

function patternmatch(pattern::LeafPattern, left, collected=Pattern[])
    pos, match = single_match(pattern, left)
    if match === nothing
        return false, left, collected
    end
    # drop the pos-th match
    left_ = vcat(left[1:pos-1], left[pos+1:end])
    samename = filter(a -> name(a) == name(pattern), collected)
    if isa(pattern.value, Int) || isa(pattern.value, Array)
        if isa(pattern.value, Int)
            increment = 1
        else
            increment = isa(match.value, AbstractString) ? [match.value] : match.value
        end
        if isempty(samename)
            match.value = increment
            return true, left_, vcat(collected, [match])
        end
        if isa(samename[1].value, Int)
            samename[1].value += increment
        elseif isa(samename[1].value, Array)
            append!(samename[1].value, increment)
        else
            @assert false
        end
        return true, left_, collected
    end
    return true, left_, vcat(collected, [match])
end

function patternmatch(pattern::Union{Optional,OptionsShortcut}, left, collected=Pattern[])
    for pat in pattern.children
        m, left, collected = patternmatch(pat, left, collected)
    end
    return true, left, collected
end

function patternmatch(pattern::Required, left, collected=Pattern[])
    l = left
    c = collected
    for pat in pattern.children
        matched, l, c = patternmatch(pat, l, c)
        if !matched
            return false, left, collected
        end
    end
    return true, l, c
end

function patternmatch(pattern::Either, left, collected=Pattern[])
    outcomes = Any[]
    for pat in pattern.children
        matched, _, _ = outcome = patternmatch(pat, left, collected)
        if matched
            push!(outcomes, outcome)
        end
    end
    if !isempty(outcomes)
        m = first(outcomes)
        for outcome in outcomes
            if length(outcome[2]) < length(m[2])
                m = outcome
            end
        end
        return m
    end
    return false, left, collected
end

function patternmatch(pattern::OneOrMore, left, collected=Pattern[])
    @assert length(pattern.children) == 1
    l = left
    c = collected
    l_ = nothing
    matched = true
    times = 0
    while matched
        matched, l, c = patternmatch(pattern.children[1], l, c)
        times += matched ? 1 : 0
        if l_ == l
            break
        end
        l_ = l
    end
    if times >= 1
        return true, l, c
    end
    return false, left, collected
end

function flat(pattern::LeafPattern, types=[])
    if isempty(types) || (typeof(pattern) in types)
        return [pattern]
    else
        return Pattern[]
    end
end

function flat(pattern::BranchPattern, types=[])
    if typeof(pattern) in types
        return [pattern]
    else
        return reduce(vcat, [flat(child, types) for child in pattern.children], init=Pattern[])
    end
end

function fix(pattern::Pattern)
    fix_identities(pattern)
    fix_repeating_arguments(pattern)
end

function fix_identities(pattern::Pattern, uniq=nothing)
    if !isa(pattern, BranchPattern)
        return pattern
    end
    uniq = uniq === nothing ? unique(flat(pattern)) : uniq
    for (i, child) in enumerate(pattern.children)
        if !isa(child, BranchPattern)
            pattern.children[i] = uniq[something(findfirst(isequal(child), uniq), 0)]
        else
            fix_identities(child, uniq)
        end
    end
end

function fix_repeating_arguments(pattern::Pattern)
    either = [child.children for child in transform(pattern).children]
    for case in either
        for el in filter(child -> count(c -> c == child, case) > 1, case)
            if isa(el, Argument) || isa(el, Option) && el.argcount > 0
                if el.value === nothing
                    el.value = []
                elseif !isa(el.value, Array)
                    el.value = split(el.value)
                end
            end
            if isa(el, Command) || isa(el, Option) && el.argcount == 0
                el.value = 0
            end
        end
    end
    return pattern
end

function transform(pattern::Pattern)
    result = Any[]
    groups = Any[Pattern[pattern]]
    while !isempty(groups)
        children = popfirst!(groups)
        parents = [Required, Optional, OptionsShortcut, Either, OneOrMore]
        if any(map(t -> t in map(typeof, children), parents))
            child = first(filter(c -> typeof(c) in parents, children))
            splice!(children, something(findfirst(isequal(child), children), 0))
            if isa(child, Either)
                for c in child.children
                    push!(groups, vcat([c], children))
                end
            elseif isa(child, OneOrMore)
                push!(groups, vcat(child.children, child.children, children))
            else
                push!(groups, vcat(child.children, children))
            end
        else
            push!(result, children)
        end
    end
    return Either([Required(r) for r in result])
end

Base.hash(pattern::Pattern) = pattern |> string |> hash

Base.getindex(tokens::Tokens, i::Integer) = tokens.tokens[i]
Base.iterate(tokens::Tokens) = isempty(tokens.tokens) ? nothing : (tokens.tokens[1], 2)
Base.iterate(tokens::Tokens, i::Int) = (i > lastindex(tokens.tokens)) ? nothing : (tokens.tokens[i], i+1)
Base.length(tokens::Tokens) = length(tokens.tokens)

move!(tokens::Tokens)   = isempty(tokens.tokens) ? nothing : popfirst!(tokens.tokens)
current(tokens::Tokens) = isempty(tokens.tokens) ? nothing : tokens[1]

# parsers
function parse_long(tokens::Tokens, options)
    # long ::= '--' chars [ ( ' ' | '=' ) chars ] ;
    long, eq, value = partition(move!(tokens), '=')
    @assert startswith(long, "--")
    value = eq == value == "" ? nothing : value
    similar = filter(o -> o.long == long, options)
    if tokens.error === DocOptExit && isempty(similar)  # if no exact match
        similar = filter(o -> o.long !== nothing && startswith(o.long, long), options)
    end
    if length(similar) > 1  # might be simply specified ambiguously 2+ times?
        throw(tokens.error("$long is not a unique prefix: $(join(map(s -> s.long, similar), ","))"))
    elseif length(similar) < 1
        argcount = eq == "=" ? 1 : 0
        o = Option(nothing, long, argcount, false)
        push!(options, o)
        if tokens.error === DocOptExit
            o = Option(nothing, long, argcount, argcount > 0 ? value : true)
        end
    else
        o = Option(similar[1].short, similar[1].long,
                   similar[1].argcount, similar[1].value)
        if o.argcount == 0
            if value !== nothing
                throw(tokens.error("$long must not have an argument"))
            end
        else
            if value === nothing
                if current(tokens) in [nothing, "--"]
                    throw(tokens.error("$long requires argument"))
                end
                value = move!(tokens)
            end
        end
        if tokens.error === DocOptExit
            o.value = value !== nothing ? value : true
        end
    end
    return [o]
end

function parse_shorts(tokens, options)
    # shorts ::= '-' ( chars )* [ [ ' ' ] chars ] ;
    token = move!(tokens)
    @assert startswith(token, '-') && !startswith(token, "--")
    left = lstrip(token, '-')
    parsed = Option[]
    while !isempty(left)
        short = string('-', left[1])
        left = left[2:end]
        similar = filter(o -> o.short == short, options)
        if length(similar) > 1
            throw(tokens.error("$short is specified ambiguously $(length(similar)) times"))
        elseif length(similar) < 1
            o = Option(short, nothing, 0, false)
            push!(options, o)
            if tokens.error === DocOptExit
                o = Option(short, nothing, 0, true)
            end
        else
            o = Option(short, similar[1].long,
                       similar[1].argcount, similar[1].value)
            value = nothing
            if o.argcount != 0
                if isempty(left)
                    if current(tokens) in [nothing, "--"]
                        throw(tokens.error("$short requires argument"))
                    end
                    value = move!(tokens)
                else
                    value = left
                    left = ""
                end
            end
            if tokens.error === DocOptExit
                o.value = value !== nothing ? value : true
            end
       end
        push!(parsed, o)
    end
    return parsed
end

function parse_expr(tokens, options)
    # expr ::= seq ( '|' seq )* ;
    seq = parse_seq(tokens, options)
    if current(tokens) != "|"
        return seq
    end
    result = length(seq) > 1 ? Pattern[Required(seq)] : seq
    while current(tokens) == "|"
        move!(tokens)
        seq = parse_seq(tokens, options)
        append!(result, length(seq) > 1 ? [Required(seq)] : seq)
    end
    return length(result) > 1 ? [Either(collect(result))] : result
end

function parse_seq(tokens, options)
    # seq ::= ( atom [ '...' ] )* ;
    result = Pattern[]
    while !(current(tokens) in [nothing, "]", ")", "|"])
        atom = parse_atom(tokens, options)
        if current(tokens) == "..."
            atom = [OneOrMore(atom)]
            move!(tokens)
        end
        append!(result, atom)
    end
    return result
end

isdash(token) = token == "-" || token == "--"

function parse_atom(tokens, options)
    # atom ::= '(' expr ')' | '[' expr ']' | 'options'
    #        | long | shorts | argument | command ;
    token = current(tokens)
    result = Pattern[]
    closing = Dict("(" => (")", Required), "[" => ("]", Optional))
    if token == "(" || token == "["
        move!(tokens)  # discard '(' or '[' token
        matching, pattern = closing[token]
        result = pattern(parse_expr(tokens, options))
        if move!(tokens) != matching
            throw(tokens.error("unmatched '$token'"))
        end
        return [result]
    elseif token == "options"
        move!(tokens)
        return [OptionsShortcut()]
    elseif startswith(token, "--") && !isdash(token)
        return parse_long(tokens, options)
    elseif startswith(token, '-') && !isdash(token)
        return parse_shorts(tokens, options)
    elseif startswith(token, '<') && endswith(token, '>') || all(isuppercase, token)
        return [Argument(move!(tokens))]
    else
        return [Command(move!(tokens))]
    end
end

function parse_argv(tokens::Tokens, options, options_first=false)
    parsed = Pattern[]
    while !isempty(tokens)
        if current(tokens) == "--"
            return append!(parsed, map(v -> Argument(nothing, v), tokens))
        elseif startswith(current(tokens), "--")
            append!(parsed, parse_long(tokens, options))
        elseif startswith(current(tokens), "-") && !isdash(current(tokens))
            append!(parsed, parse_shorts(tokens, options))
        elseif options_first
            return append!(parsed, map(v -> Argument(nothing, v), tokens))
        else
            push!(parsed, Argument(nothing, move!(tokens)))
        end
    end
    return parsed
end

function parse_pattern(source, options)
    tokens = Tokens(source)
    result = parse_expr(tokens, options)
    return Required(result)
end

function parse_section(name, source)
    pattern = Regex("^([^\\n]*$name[^\\n]*\\n?(?:[ \\t].*?(?:\\n|\$))*)", "im")
    map(strip, collect((m.match for m in eachmatch(pattern, source))))
end

function parse_defaults(doc)
    defaults = Option[]
    for s in parse_section("options:", doc)
        _, _, s = partition(s, ':')
        sp = split(s, "\n")
        sp = map(strip, sp)
        sp = filter!(s -> startswith(s, '-'), sp)
        options = map(Option, sp)
        append!(defaults, options)
    end
    return defaults
end

function formal_usage(section)
    _, _, section = partition(section, ':')
    words = split(strip(section))
    program = popfirst!(words)
    patterns = AbstractString[]
    for w in words
        if w == program
            push!(patterns, ") | (")
        else
            push!(patterns, w)
        end
    end
    return string("( ", join(patterns, ' '), " )")
end

function extras(help, version, options, doc)
    if help && any(o -> name(o) in ["-h", "--help"] && o.value, options)
        println(rstrip(doc, '\n'))
        isinteractive() || exit(0)
    end
    if version !== nothing && any(o -> name(o) == "--version" && o.value , options)
        println(version)
        isinteractive() || exit(0)
    end
end

"""
    docopt(doc::AbstractString,
           args=ARGS;
           version=nothing,
           help::Bool=true,
           options_first::Bool=false,
           exit_on_error::Bool=true)

Parse command-line arguments according to a help message.

Parsed command-line arguments are retuned as a dictionary of arguments of type
`Dict{AbstractString,Any}`; keys are argument names or flag names, and values
are argument values passed to the command-line arguments.

See http://docopt.org/ for the description language of help.

# Arguments
* `doc`: description of your command-line interface.
* `args=ARGS`: argument vector to be parsed.
* `version=nothing`: version of your command-line tool (e.g. `v"1.0.2"`).
* `help=true`: show the help when '-h' or '--help' is passed.
* `options_first=false`: force options to precede positional arguments.
* `exit_on_error=true`: print the usage and exit when parsing error happens.
"""
function docopt(doc::AbstractString,
                args=ARGS;
                version=nothing,
                help::Bool=true,
                options_first::Bool=false,
                exit_on_error::Bool=true)
    usage_sections = parse_section("usage:", doc)
    if isempty(usage_sections)
        throw(DocOptLanguageError("\"usage:\" (case-insensitive) not found."))
    elseif length(usage_sections) > 1
        throw(DocOptLanguageError("More than one \"usage:\" (case-insensitive)."))
    end
    docoptexit = DocOptExit(usage_sections[1])
    options = parse_defaults(doc)
    pattern = parse_pattern(formal_usage(docoptexit.usage), options)
    args = parse_argv(Tokens(args, DocOptExit), options, options_first)
    pattern_options = Set(flat(pattern, [Option]))
    for options_shortcut in flat(pattern, [OptionsShortcut])
        doc_options = parse_defaults(doc)
        options_shortcut.children = Pattern[x for x in setdiff(Set(doc_options), pattern_options)]
    end
    extras(help, version, args, doc)
    matched, left, collected = patternmatch(fix(pattern), args)
    if matched && isempty(left)
        ret = Dict{String,Any}()
        for a in vcat(flat(pattern), collected)
            ret[name(a)] = a.value
        end
        return ret
    end
    if exit_on_error
        @printf(stderr, "%s\n", docoptexit.usage)
        isinteractive() || exit(1)
    else
        throw(docoptexit)
    end
end

end  # DocOpt
