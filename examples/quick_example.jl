doc = """Usage:
  quick_example.py tcp <host> <port> [--timeout=<seconds>]
  quick_example.py serial <port> [--baud=9600] [--timeout=<seconds>]
  quick_example.py -h | --help | --version

"""

import Docopt: docopt

arguments = docopt(doc; version=v"0.1.1")
dump(arguments)
