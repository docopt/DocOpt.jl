# DocOpt.jl

[![Build Status](https://travis-ci.org/docopt/DocOpt.jl.svg?branch=master)](https://travis-ci.org/docopt/DocOpt.jl)

**DocOpt.jl** is a port of [**docopt**](http://docopt.org/) written in the [Julia](http://julialang.org/) language.

**docopt** generates a command-line arguments parser from human-readable usage patterns.

You will find how attractive the idea of **docopt** is with the example below:

```julia
doc = """Naval Fate.

Usage:
  naval_fate.jl ship new <name>...
  naval_fate.jl ship <name> move <x> <y> [--speed=<kn>]
  naval_fate.jl ship shoot <x> <y>
  naval_fate.jl mine (set|remove) <x> <y> [--moored|--drifting]
  naval_fate.jl -h | --help
  naval_fate.jl --version

Options:
  -h --help     Show this screen.
  --version     Show version.
  --speed=<kn>  Speed in knots [default: 10].
  --moored      Moored (anchored) mine.
  --drifting    Drifting mine.

"""

using DocOpt  # import docopt function

args = docopt(doc, version=v"2.0.0")
```

The result is:

```
$ julia -qL examples/naval_fate.jl ship new FOO
julia> args
Dict{String,Any} with 15 entries:
  "remove"     => false
  "--help"     => false
  "<name>"     => String["FOO"]
  "--drifting" => false
  "mine"       => false
  "move"       => false
  "--version"  => false
  "--moored"   => false
  "<x>"        => nothing
  "ship"       => true
  "new"        => true
  "shoot"      => false
  "set"        => false
  "<y>"        => nothing
  "--speed"    => "10"

```

Julia v0.6 is now supported.


## API

The `DocOpt` module exports just one function, `docopt`, which takes multiple
arguments but all of them except the first one are optional.

```julia
docopt(doc::AbstractString, argv=ARGS; help=true, version=nothing, options_first=false, exit_on_error=true)
```

**Arguments**

* `doc` : Description of your command-line interface. (type: `AbstractString`)
* `argv` : Argument vector to be parsed. (type: `String` or `Vector{String}`, default: `ARGS`)
* `help` : Set to `false` to disable automatic help on -h or --help options. (type: `Bool`, default: `true`)
* `version` : If passed, the value will be printed if --version is in `argv`. (any type, but `VersionNumber` is recommended, e.g. v"1.0.2")
* `options_first` : Set to `true` to require options precedes positional arguments, i.e. to forbid options and positional arguments intermix. (type: `Bool`, default: `false`)
* `exit_on_error` : Set to `true` to print the usage and exit when parsing error happens. This option is for unit testing. (type: `Bool`, default: `true`)

`doc` argument is mandatory, `argv` argument is automatically set to command-line arguments, and `help`, `version`, `options_first` and `exit_on_error` are keyword arguments.

**Return**

* parsed arguments : An associative collection, where keys are names of command-line elements such as e.g. "--verbose" and "<path>", and values are the parsed values of those elements. (type: `Dict{String,Any}`)

See <http://docopt.org/> for more details about the grammar of the usage pattern.
