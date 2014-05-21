# DocOpt.jl

**DocOpt.jl** is a port of [**docopt**](http://docopt.org/) written in the [Julia](http://julialang.org/) language.

**docopt** generates a command-line arguments parser from human-readable usage patterns.

You will find how attractive the idea of **docopt** is with the example below:

```julia
doc = """Naval Fate.

Usage:
  naval_fate.py ship new <name>...
  naval_fate.py ship <name> move <x> <y> [--speed=<kn>]
  naval_fate.py ship shoot <x> <y>
  naval_fate.py mine (set|remove) <x> <y> [--moored|--drifting]
  naval_fate.py -h | --help
  naval_fate.py --version

Options:
  -h --help     Show this screen.
  --version     Show version.
  --speed=<kn>  Speed in knots [default: 10].
  --moored      Moored (anchored) mine.
  --drifting    Drifting mine.

"""

using DocOpt  # import docopt function

arguments = docopt(doc, version=v"2.0.0")
dump(arguments)
```

Julia v0.3.0 (prerelease) or later is now supported.

## API

`DocOpt` module exports just one function (`docopt`), which takes only few arguments and most of them are optional.

```julia
docopt(doc::String, argv=ARGS; help=true, version=nothing, options_first=false, exit_on_error=true)
```

**Parameters**

* `doc` : Description of your command-line interface. (type: `String`)
* `argv` : Argument vector to be parsed. (type: `String` or `Array{String}`, default: `ARGS`)
* `help` : Set to `false` to disable automatic help on -h or --help options. (type: `Bool`, default: `true`)
* `version` : If passed, the value will be printed if --version is in `argv`. (any type, but `VersionNumber` is recommended, i.e. v"1.0.2")
* `options_first` : Set to `true` to require options precedes positional arguments, i.e. to forbid options and positional arguments intermix. (type: `Bool`, default: `false`)
* `exit_on_error` : Set to `true` to print the usage and exit when parsing error happens. This option is for unit testing. (type: `Bool`, default: `true`)

`doc` argument is mandatory, `argv` argument is automatically set to command-line arguments, and `help`, `version`, `options_first` and `exit_on_error` are keyword arguments.


**Returns**

* parsed arguemnts : An associative collection, where keys are names of command-line elements such as e.g. "--verbose" and "<path>", and values are the parsed values of those elements. (type: `Dict{String, Any}`)

See <http://docopt.org/> for more details about the grammar of the usage pattern.
