const doc = """Usage:
  quick_example.jl tcp <host> <port> [--timeout=<seconds>]
  quick_example.jl serial <port> [--baud=9600] [--timeout=<seconds>]
  quick_example.jl -h | --help | --version

"""

using DocOpt

args = docopt(doc, version=v"0.1.1")
