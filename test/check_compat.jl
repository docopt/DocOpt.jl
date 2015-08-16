# check the compatibility to the original docopt

using DocOpt
using Compat

immutable Token
    kind::Symbol
    value
end

immutable UserError; end

const user_error = "user-error"

function readuntil_or_error(io, delim)
    v = readuntil(io, delim)
    if !endswith(v, delim)
        error("'$delim' is expected")
    end
    # strip delim
    v[1:end-length(delim)]
end

function expects(io, s)
    for i in 1:length(s)
        @assert read(io, Char) == s[i]
    end
end

function read_char(io)
    c = read(io, Char)
    while c == '#'
        readuntil(io, '\n')
        c = read(io, Char)
    end
    c
end

# tokenizer of testcases of docopt
function token(io)
    # read char
    eof(io) && return Token(:eof, ())
    char = read_char(io)
    while isspace(char)
        eof(io) && return Token(:eof, ())
        char = read_char(io)
    end

    value = ()
    if char == 'r'
        kind = :docstring
        expects(io, "\"\"\"")
        value = readuntil_or_error(io, "\"\"\"")
    elseif char == '$'
        kind = :argument
        expects(io, " ")
        value = readuntil_or_error(io, '\n')
    elseif char == '{'
        kind = :lbrace
    elseif char == '}'
        kind = :rbrace
    elseif char == '['
        kind = :lbracket
    elseif char == ']'
        kind = :rbracket
    elseif char == ':'
        kind = :colon
    elseif char == ','
        kind = :comma
    elseif char == '"'
        kind = :string
        value = readuntil_or_error(io, '"')
    elseif char == 't'
        kind = :bool
        expects(io, "rue")
        value = true
    elseif char == 'f'
        kind = :bool
        expects(io, "alse")
        value = false
    elseif char == 'n'
        kind = :null
        expects(io, "ull")
        value = nothing
    elseif isdigit(char)
        kind = :number
        value = parse(Int, string(char))
    else
        error("unknown token")
    end
    Token(kind, value)
end

# parsers take an IO stream and a current token, then return a parsed value and a next token

function parse_testcases(io, t)
    testcases = Any[]
    while t.kind !== :eof
        testcase, t = parse_testcase(io, t)
        push!(testcases, testcase)
    end
    testcases, t
end

function parse_testcase(io, t)
    @assert t.kind === :docstring
    docstring = t.value
    t = token(io)
    pairs, t = parse_pairs(io, t)
    (docstring, pairs), t
end

function parse_pairs(io, t)
    @assert t.kind === :argument
    pairs = Any[]
    while t.kind === :argument
        arg = t.value
        res, t = parse_result(io, token(io))
        push!(pairs, (arg, res))
    end
    pairs, t
end

function parse_result(io, t)
    if t.kind === :string
        @assert t.value == user_error
        return UserError, token(io)
    end
    @assert t.kind === :lbrace
    result = Dict{String,Any}()
    t = token(io)
    while t.kind !== :rbrace
        (key, value), t = parse_keyvalue(io, t)
        result[key] = value
        t.kind === :comma && (t = token(io))
    end
    @assert t.kind === :rbrace
    result, token(io)
end

function parse_keyvalue(io, t)
    @assert t.kind === :string
    key = t.value
    t = token(io)
    @assert t.kind === :colon
    t = token(io)
    value, t = parse_value(io, t)
    (key, value), t
end

function parse_value(io, t)
    if t.kind ∈ [:string, :bool, :null, :number]
        return t.value, token(io)
    elseif t.kind === :lbracket
        values = Any[]
        t = token(io)
        while t.kind !== :rbracket
            value, t = parse_value(io, t)
            push!(values, value)
            t.kind === :comma && (t = token(io))
        end
        return values, token(io)
    end
    error("invalid token where a value is expected: $t")
end

let
    # language-agnostic test cases from:
    #   https://github.com/docopt/docopt/blob/master/testcases.docopt
    open("test/testcases.docopt") do f
        t = token(f)
        testcases, _ = parse_testcases(f, t)
        for (docstring, pairs) in testcases
            println("-"^60)
            print(docstring)
            for (arg, expected) in pairs
                println(arg)
                args = split(replace(arg, r"prog\s*", ""), r"\s+")
                args = filter!(a -> !isempty(a), args)
                local result
                try
                    result = docopt(docstring, args, exit_on_error=false)
                catch ex
                    if isa(ex, DocOpt.DocOptExit)
                        result = UserError
                    else
                        rethrow()
                    end
                end
                if result == expected
                    println("=> OK")
                else
                    println("=> NOT OK")
                    @show result expected
                end
                println()
            end
        end
    end
end
