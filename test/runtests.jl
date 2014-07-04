module TestDocOpt

using Base.Test
using DocOpt  # import docopt method
import DocOpt: DocOptExit,
               DocOptLanguageError,
               # patterns
               Option,
               Argument,
               Command,
               Required,
               Optional,
               OneOrMore,
               Either,
               OptionsShortcut,
               # internal methods (only common ones)
               patternmatch,
               fix,
               fix_identities

function test_pattern_flat()
    flat = DocOpt.flat

    @test flat(Required([OneOrMore([Argument("N")]),
                         Option("-a"),
                         Argument("M")])) ==
        [Argument("N"), Option("-a"), Argument("M")]
    @test flat(Required([Optional([OptionsShortcut()]),
                         Optional([Option("-a", nothing)])]),
               [OptionsShortcut]) ==
        [OptionsShortcut()]
end

function test_option()
    @test Option("-h") == Option("-h", nothing, 0, false)
    @test Option("--help") == Option(nothing, "--help", 0, false)
    @test Option("-h --help") == Option("-h", "--help", 0, false)
    @test Option("-h, --help") == Option("-h", "--help", 0, false)

    @test Option("-h TOPIC") == Option("-h", nothing, 1, nothing)
    @test Option("--help TOPIC") == Option(nothing, "--help", 1, nothing)
    @test Option("-h TOPIC --help TOPIC") == Option("-h", "--help", 1, nothing)
    @test Option("-h TOPIC, --help TOPIC") == Option("-h", "--help", 1, nothing)
    @test Option("-h TOPIC, --help=TOPIC") == Option("-h", "--help", 1, nothing)

    @test Option("-h  Description...") == Option("-h", nothing, 0, false)
    @test Option("-h --help  Description...") == Option("-h", "--help", 0, false)
    @test Option("-h TOPIC  Description...") == Option("-h", nothing, 1, nothing)

    @test Option("     -h") == Option("-h", nothing, 0, false)

    @test Option("-h TOPIC  Description... [default: 2]") == Option("-h", nothing, 1, "2")
    @test Option("-h TOPIC  Description... [default: topic-1]") == Option("-h", nothing, 1, "topic-1")
    @test Option("--help=TOPIC  ... [default: 3.14]") ==  Option(nothing, "--help", 1, "3.14")
    @test Option("-h, --help=DIR  ... [default: ./]") ==  Option("-h", "--help", 1, "./")
    @test Option("-h TOPIC  Descripton... [dEfAuLt: 2]") == Option("-h", nothing, 1, "2")
end

function test_option_name()
    name = DocOpt.name

    @test name(Option("-h", nothing)) == "-h"
    @test name(Option("-h", "--help")) == "--help"
    @test name(Option(nothing, "--help")) == "--help"
end

function test_commands()
    @test docopt("Usage: prog add", "add") == {"add" => true}
    @test docopt("Usage: prog [add]", "") == {"add" => false}
    @test docopt("Usage: prog [add]", "add") == {"add" => true}
    @test docopt("Usage: prog (add|rm)", "add") == {"add" => true, "rm" => false}
    @test docopt("Usage: prog (add|rm)", "rm") == {"add" => false, "rm" => true}
    @test docopt("Usage: prog a b", "a b") == {"a" => true, "b" => true}

    @test_throws DocOptExit docopt("Usage: prog a b", "b a"; exit_on_error=false)
end

function test_formal_usage()
    doc = """
    Usage: prog [-hv] ARG
           prog N M

    prog is a program."""

    usage, = DocOpt.parse_section("usage:", doc)
    @test usage == "Usage: prog [-hv] ARG\n       prog N M"
    @test DocOpt.formal_usage(usage) == "( [-hv] ARG ) | ( N M )"
end

function test_parse_argv()
    o = [Option("-h"), Option("-v", "--verbose"), Option("-f", "--file", 1)]
    ts = s -> DocOpt.Tokens(s, DocOptExit)
    parse_argv = DocOpt.parse_argv

    @test parse_argv(ts(""), o) == []
    @test parse_argv(ts("-h"), o) == [Option("-h", nothing, 0, true)]
    @test parse_argv(ts("-h --verbose"), o) == [Option("-h", nothing, 0, true), Option("-v", "--verbose", 0, true)]
    @test parse_argv(ts("-h --file f.txt"), o) == [Option("-h", nothing, 0, true), Option("-f", "--file", 1, "f.txt")]
    @test parse_argv(ts("-h --file f.txt arg"), o) == [
        Option("-h", nothing, 0, true),
        Option("-f", "--file", 1, "f.txt"),
        Argument(nothing, "arg")
    ]
    @test parse_argv(ts("-h --file f.txt arg arg2"), o) == [
        Option("-h", nothing, 0, true),
        Option("-f", "--file", 1, "f.txt"),
        Argument(nothing, "arg"),
        Argument(nothing, "arg2")
    ]
    @test parse_argv(ts("-h arg -- -v"), o) == [
        Option("-h", nothing, 0, true),
        Argument(nothing, "arg"),
        Argument(nothing, "--"),
        Argument(nothing, "-v")
    ]
end

function test_parse_pattern()
    o = [Option("-h"), Option("-v", "--verbose", 0, false), Option("-f", "--file", 1, nothing)]
    parse_pattern = DocOpt.parse_pattern

    @test parse_pattern("[ -h ]", o) == Required([Optional([Option("-h")])])
    @test parse_pattern("[ ARG ...]", o) == Required([Optional([OneOrMore([Argument("ARG")])])])
    @test parse_pattern("[ -h | -v ]", o) == Required([Optional([Either([Option("-h"),
                                                                         Option("-v", "--verbose")])])])
    @test parse_pattern("( -h | -v [ --file <f> ] )", o) ==
        Required([Required([
            Either([Option("-h", nothing, 0, false),
                    Required([Option("-v", "--verbose", 0, false),
                              Optional([Option("-f", "--file", 1, nothing)])])])])])
    @test parse_pattern("(-h|-v[--file=<f>]N...)", o) ==
        Required([Required([Either([Option("-h"),
                                    Required([Option("-v", "--verbose"),
                                              Optional([Option("-f", "--file", 1, nothing)]),
                                              OneOrMore([Argument("N")])])])])])
    @test parse_pattern("(N [M | (K | L)] | O P)", []) ==
        Required([Required([Either([Required([Argument("N"),
                                              Optional([Either([Argument("M"),
                                                                Required([Either([Argument("K"),
                                                                                  Argument("L")])])])])]),
                                    Required([Argument("O"),
                                              Argument("P")])])])])
    @test parse_pattern("[ -h ] [N]", o) ==
        Required([Optional([Option("-h")]),
                  Optional([Argument("N")])])
    @test parse_pattern("[options]", o) == Required([Optional([OptionsShortcut()])])
    @test parse_pattern("[options] A", o) ==
        Required([Optional([OptionsShortcut()]),
                  Argument("A")])
    @test parse_pattern("-v [options]", o) ==
        Required([Option("-v", "--verbose", 0, false),
                  Optional([OptionsShortcut()])])
    @test parse_pattern("ADD", o) == Required([Argument("ADD")])
    @test parse_pattern("<add>", o) == Required([Argument("<add>")])
    @test parse_pattern("add", o) == Required([Command("add")])
end

function test_option_match()
    @test patternmatch(Option("-a", nothing, 0, false), [Option("-a", nothing, 0, true)]) ==
        (true, [], [Option("-a", nothing, 0, true)])
    @test patternmatch(Option("-a", nothing, 0, false), [Option("-x", nothing, 0, false)]) ==
        (false, [Option("-x", nothing, 0, false)], [])
    @test patternmatch(Option("-a", nothing, 0, false), [Argument("N")]) ==
        (false, [Argument("N")], [])
    @test patternmatch(Option("-a", nothing, 0, false), [Option("-x", nothing, 0, false),
                                                         Option("-a", nothing, 0, false),
                                                         Argument("N")]) ==
        (true, [Option("-x", nothing, 0, false), Argument("N")], [Option("-a")])
    @test patternmatch(Option("-a", nothing, 0, false), [Option("-a", nothing, 0, true),
                                                         Option("-a", nothing, 0, false)]) ==
        (true, [Option("-a", nothing, 0, false)], [Option("-a", nothing, 0, true)])
end

function test_argument_match()
    @test patternmatch(Argument("N"), [Argument(nothing, 9)]) ==
        (true, [], [Argument("N", 9)])
    @test patternmatch(Argument("N"), [Option("-x")]) ==
        (false, [Option("-x", nothing, 0, false)], [])
    @test patternmatch(Argument("N"), [Option("-x"), Option("-a"), Argument(nothing, 5)]) ==
        (true, [Option("-x"), Option("-a")], [Argument("N", 5)])
    @test patternmatch(Argument("N"), [Argument(nothing, 9), Argument(nothing, 0)]) ==
        (true, [Argument(nothing, 0)], [Argument("N", 9)])
end

function test_command_match()
    @test patternmatch(Command("c"), [Argument(nothing, "c")]) ==
        (true, [], [Command("c", true)])
    @test patternmatch(Command("c"), [Option("-x")]) ==
        (false, [Option("-x")], [])
    @test patternmatch(Command("c"), [Option("-x"), Option("-a"), Argument(nothing, "c")]) ==
        (true, [Option("-x"), Option("-a")], [Command("c", true)])
    @test patternmatch(Either([Command("add", false), Command("rm", false)]), [Argument(nothing, "rm")]) ==
        (true, [], [Command("rm", true)])
end

function test_optional_match()
    @test patternmatch(Optional([Option("-a")]), [Option("-a")]) ==
        (true, [], [Option("-a")])
    @test patternmatch(Optional([Option("-a")]), []) ==
        (true, [], [])
    @test patternmatch(Optional([Option("-a")]), [Option("-x")]) ==
        (true, [Option("-x")], [])
    @test patternmatch(Optional([Option("-a"), Option("-b")]), [Option("-a")]) ==
        (true, [], [Option("-a")])
    @test patternmatch(Optional([Option("-a"), Option("-b")]), [Option("-b")]) ==
        (true, [], [Option("-b")])
    @test patternmatch(Optional([Option("-a"), Option("-b")]), [Option("-x")]) ==
        (true, [Option("-x")], [])
    @test patternmatch(Optional([Argument("N")]), [Argument(nothing, 9)]) ==
        (true, [], [Argument("N", 9)])
    @test patternmatch(Optional([Option("-a"), Option("-b")]), [Option("-b"), Option("-x"), Option("-a")]) ==
        (true, [Option("-x")], [Option("-a"), Option("-b")])
end

function test_required_match()
    @test patternmatch(Required([Option("-a")]), [Option("-a")]) ==
        (true, [], [Option("-a")])
    @test patternmatch(Required([Option("-a")]), []) ==
        (false, [], [])
    @test patternmatch(Required([Option("-a")]), [Option("-x")]) ==
        (false, [Option("-x")], [])
    @test patternmatch(Required([Option("-a"), Option("-b")]), [Option("-a")]) ==
        (false, [Option("-a")], [])
end

function test_either_match()
    @test patternmatch(Either([Option("-a", nothing, 0, nothing), Option("-b", nothing, 0, nothing)]), [Option("-a", nothing, 0, nothing)]) ==
        (true, [], [Option("-a", nothing, 0, nothing)])
    @test patternmatch(Either([Option("-a", nothing, 0, nothing), Option("-b", nothing, 0, nothing)]), [Option("-a", nothing, 0, nothing), Option("-b", nothing, 0, nothing)]) ==
        (true, [Option("-b", nothing, 0, nothing)], [Option("-a", nothing, 0, nothing)])
    @test patternmatch(Either([Option("-a", nothing, 0, nothing), Option("-b", nothing, 0, nothing)]), [Option("-x", nothing, 0, nothing)]) ==
        (false, [Option("-x", nothing, 0, nothing)], [])
    @test patternmatch(Either([Option("-a", nothing, 0, nothing), Option("-b", nothing, 0, nothing), Option("-c", nothing, 0, nothing)]), [Option("-x", nothing, 0, nothing), Option("-b", nothing, 0, nothing)]) ==
        (true, [Option("-x", nothing, 0, nothing)], [Option("-b", nothing, 0, nothing)])
    @test patternmatch(Either([Argument("M"),
                               Required([Argument("N"), Argument("M")])]),
                       [Argument(nothing, 1), Argument(nothing, 2)]) ==
        (true, [], [Argument("N", 1), Argument("M", 2)])
end

function test_one_or_more_match()
    @test patternmatch(OneOrMore([Argument("N")]), [Argument(nothing, 9)]) ==
        (true, [], [Argument("N", 9)])
    @test patternmatch(OneOrMore([Argument("N")]), []) ==
        (false, [], [])
    @test patternmatch(OneOrMore([Argument("N")]), [Option("-x", nothing, 0, nothing)]) ==
        (false, [Option("-x", nothing, 0, nothing)], [])
    @test patternmatch(OneOrMore([Argument("N")]), [Argument(nothing, 9), Argument(nothing, 8)]) ==
        (true, [], [Argument("N", 9), Argument("N", 8)])
    @test patternmatch(OneOrMore([Argument("N")]), [Argument(nothing, 9), Option("-x", nothing, 0, nothing), Argument(nothing, 8)]) ==
        (true, [Option("-x", nothing, 0, nothing)], [Argument("N", 9), Argument("N", 8)])
    @test patternmatch(OneOrMore([Option("-a")]), [Option("-a"), Argument(nothing, 8), Option("-a")]) ==
        (true, [Argument(nothing, 8)], [Option("-a"), Option("-a")])
    @test patternmatch(OneOrMore([Option("-a")]), [Argument(nothing, 8), Option("-x")]) ==
        (false, [Argument(nothing, 8), Option("-x")], [])
    @test patternmatch(OneOrMore([Required([Option("-a"), Argument("N")])]), [Option("-a"), Argument(nothing, 1), Option("-x"), Option("-a"), Argument(nothing, 2)]) ==
        (true, [Option("-x")], [Option("-a"), Argument("N", 1), Option("-a"), Argument("N", 2)])
    @test patternmatch(OneOrMore([Optional([Argument("N")])]), [Argument(nothing, 9)]) ==
        (true, [], [Argument("N", 9)])
end

function test_list_argument_match()
    @test patternmatch(fix(Required([Argument("N"), Argument("N")])),
                       [Argument(nothing, "1"), Argument(nothing, "2")]) ==
        (true, [], [Argument("N", ["1", "2"])])
    @test patternmatch(fix(OneOrMore([Argument("N")])),
                       [Argument(nothing, "1"), Argument(nothing, "2"), Argument(nothing, "3")]) ==
        (true, [], [Argument("N", ["1", "2", "3"])])
    @test patternmatch(fix(Required([Argument("N"), OneOrMore([Argument("N")])])),
                       [Argument(nothing, "1"), Argument(nothing, "2"), Argument(nothing, "3")]) ==
        (true, [], [Argument("N", ["1", "2", "3"])])
    @test patternmatch(fix(Required([Argument("N"), Required([Argument("N")])])),
                       [Argument(nothing, "1"), Argument(nothing, "2")]) ==
        (true, [], [Argument("N", ["1", "2"])])
end

function test_basic_pattern_matching()
    # ( -a N [ -x Z ] )
    pattern = Required([Option("-a"), Argument("N"),
                        Optional([Option("-x"), Argument("Z")])])

    # -a N
    @test patternmatch(pattern, [Option("-a"), Argument(nothing, 9)]) ==
        (true, [], [Option("-a"), Argument("N", 9)])

    # -a -x N Z
    @test patternmatch(pattern, [Option("-a"), Option("-x"),
                                 Argument(nothing, 9), Argument(nothing, 5)]) ==
        (true, [], [Option("-a"), Argument("N", 9), Option("-x"), Argument("Z", 5)])

    # -x N Z
    @test patternmatch(pattern, [Option("-x"), Argument(nothing, 9), Argument(nothing, 5)]) ==
        (false, [Option("-x"), Argument(nothing, 9), Argument(nothing, 5)], [])
end

function test_pattern_either()
    transform = DocOpt.transform

    @test transform(Option("-a")) == Either([Required([Option("-a")])])
    @test transform(Argument("A")) == Either([Required([Argument("A")])])
    @test transform(Required([Either([Option("-a"), Option("-b")]),
                              Option("-c")])) ==
        Either([Required([Option("-a"), Option("-c")]),
                Required([Option("-b"), Option("-c")])])
    @test transform(Optional([Option("-a"), Either([Option("-b"), Option("-c")])])) ==
        Either([Required([Option("-b"), Option("-a")]),
                Required([Option("-c"), Option("-a")])])
    @test transform(Either([Option("-x"), Either([Option("-y"), Option("-z")])])) ==
        Either([Required([Option("-x")]),
                Required([Option("-y")]),
                Required([Option("-z")])])
    @test transform(OneOrMore([Argument("N"), Argument("M")])) ==
        Either([Required([Argument("N"), Argument("M"),
                          Argument("N"), Argument("M")])])
end

function test_pattern_fix_repeating_arguments()
    fix_repeating_arguments = DocOpt.fix_repeating_arguments

    @test fix_repeating_arguments(Option("-a")) == Option("-a")
    @test fix_repeating_arguments(Argument("N", nothing)) == Argument("N", nothing)
    @test fix_repeating_arguments(Required([Argument("N"), Argument("N")])) ==
        Required([Argument("N", {}), Argument("N", {})])
    @test fix(Either([Argument("N"), OneOrMore([Argument("N")])])) ==
        Either([Argument("N", {}), OneOrMore([Argument("N", {})])])
end

function test_set()
    @test Argument("N") == Argument("N")
    @test Set([Argument("N"), Argument("N")]) == Set([Argument("N")])
end

function test_pattern_fix_identities_1()
    pattern = Required([Argument("N"), Argument("N")])

    @test pattern.children[1] == pattern.children[2]
    @test pattern.children[1] !== pattern.children[2]
    fix_identities(pattern)
    @test pattern.children[1] === pattern.children[2]
end

function test_pattern_fix_identities_2()
    pattern = Required([Optional([Argument("X"), Argument("N")]), Argument("N")])

    @test pattern.children[1].children[2] == pattern.children[2]
    @test pattern.children[1].children[2] !== pattern.children[2]
    fix_identities(pattern)
    @test pattern.children[1].children[2] === pattern.children[2]
end

function test_long_options_error_handling()
    @test_throws DocOptExit docopt("Usage: prog", "--non-existent"; exit_on_error=false)
    @test_throws DocOptExit docopt("Usage: prog [--version --verbose]\nOptions: --version\n --verbose", "--ver"; exit_on_error=false)

    @test_throws DocOptLanguageError docopt("Usage: prog --long\nOptions: --long ARG"; exit_on_error=false)

    @test_throws DocOptExit docopt("Usage: prog --long ARG\nOptions: --long ARG", "--long"; exit_on_error=false)

    @test_throws DocOptLanguageError docopt("Usage: prog --long=ARG\nOptions: --long"; exit_on_error=false)

    @test_throws DocOptExit docopt("Usage: prog --long\nOptions: --long", "--long=ARG"; exit_on_error=false)
end

function test_short_options_error_handling()
    @test_throws DocOptLanguageError docopt("Usage: prog -x\nOptions: -x  this\n -x  that"; exit_on_error=false)
    @test_throws DocOptExit docopt("Usage: prog", "-x"; exit_on_error=false)
    @test_throws DocOptLanguageError docopt("Usage: prog -o\nOptions: -o ARG"; exit_on_error=false)
    @test_throws DocOptExit docopt("Usage: prog -o ARG\nOptions: -o ARG", "-o"; exit_on_error=false)
end

function test_matching_paren()
    @test_throws DocOptLanguageError docopt("Usage: prog [a [b]"; exit_on_error=false)

    # DocOptLanguageError
    #@test_throws DocOptLanguageError docopt("Usage: prog [a [b] ] c)"; exit_on_error=false)
end

function test_allow_double_dash()
    @test docopt("usage: prog [-o] [--] <arg>\nkptions: -o", "-- -o") ==
        {"-o" => false, "<arg>" => "-o", "--" => true}
    @test docopt("usage: prog [-o] [--] <arg>\nkptions: -o", "-o 1") ==
        {"-o" => true, "<arg>" => "1", "--" => false}

    @test_throws DocOptExit docopt("usage: prog [-o] <arg>\noptions:-o", "-- -o"; exit_on_error=false)
end

function test_docopt()
    doc = """Usage: prog [-v] A

             Options: -v  Be verbose."""

    @test docopt(doc, "arg") == {"-v" => false, "A" => "arg"}
    @test docopt(doc, "-v arg") == {"-v" => true, "A" => "arg"}

    doc = """Usage: prog [-vqr] [FILE]
              prog INPUT OUTPUT
              prog --help

    Options:
      -v  print status messages
      -q  report only file names
      -r  show all occurrences of the same error
      --help

    """

    a = docopt(doc, "-v file.jl")
    @test a == {"-v" => true, "-q" => false, "-r" => false, "--help" => false,
                "FILE" => "file.jl", "INPUT" => nothing, "OUTPUT" => nothing}

    a = docopt(doc, "-v")
    @test a == {"-v" => true, "-q" => false, "-r" => false, "--help" => false,
                "FILE" => nothing, "INPUT" => nothing, "OUTPUT" => nothing}

    @test_throws DocOptExit docopt(doc, "-v input.jl output.jl"; exit_on_error=false)
    @test_throws DocOptExit docopt(doc, "--fake"; exit_on_error=false)

    # SystemExit (in Python)
    #@test_throws Exception docopt(doc, "--hel"; exit_on_error=false)
end

function test_language_errors()
    @test_throws DocOptLanguageError docopt("no usage with colon here"; exit_on_error=false)
    @test_throws DocOptLanguageError docopt("usage: here \n\n and again usage: here"; exit_on_error=false)
end

function test_issue_40()
    # SystemExit (in Python)
    # NOTE: This test really exits the program and the rest of the tests will be ignored!
    #@test_throws docopt("usage: prog --help-commands | --help", "--help")

    @test docopt("usage: prog --aabb | --aa", "--aa") == {"--aabb" => false, "--aa" => true}
end

function test_issue_34_unicode_strings()
    @test docopt(utf8("usage: prog [-o <a>]"), "") ==
        {"-o" => false, "<a>" => nothing}
end

function test_count_multiple_flags()
    @test docopt("usage: prog [-v]", "-v") == {"-v" => true}
    @test docopt("usage: prog [-vv]", "") == {"-v" => 0}
    @test docopt("usage: prog [-vv]", "-v") == {"-v" => 1}
    @test docopt("usage: prog [-vv]", "-vv") == {"-v" => 2}
    @test_throws DocOptExit docopt("usage: prog [-vv]", "-vvv"; exit_on_error=false)
    @test docopt("usage: prog [-v | -vv | -vvv]", "-vvv") == {"-v" => 3}
    @test docopt("usage: prog -v...", "-vvvvvv") == {"-v" => 6}
    @test docopt("usage: prog [--ver --ver]", "--ver --ver") == {"--ver" => 2}
end

function test_any_options_parameter()
    doc = "usage: prog [options]"
    @test_throws DocOptExit docopt(doc, "-foo --bar --spam=eggs"; exit_on_error=false)
    @test_throws DocOptExit docopt(doc, "--foo --bar --bar"; exit_on_error=false)
    @test_throws DocOptExit docopt(doc, "--bar --bar --bar -ffff"; exit_on_error=false)
    @test_throws DocOptExit docopt(doc, "--long=arg, --long=another"; exit_on_error=false)
end

function test_default_value_for_positional_arguments()
    doc = """Usage: prog [--data=<data>...]\n
             Options:
             \t-d --data=<arg>    Input data [default: x]
          """
    a = docopt(doc, "")
    @test a == {"--data" => ["x"]}

    doc = """Usage: prog [--data=<data>...]\n
             Options:
             \t-d --data=<arg>    Input data [default: x y]
          """
    a = docopt(doc, "")
    @test a == {"--data" => ["x", "y"]}

    a = docopt(doc, "--data=this")
    @test a == {"--data" => ["this"]}
end

function test_issue_59()
    @test docopt("usage: prog --long=<a>", "--long=") == {"--long" => ""}
    @test docopt("""usage: prog -l <a>
                    options: -l <a>""", ["-l", ""]) == {"-l" => ""}
end

function test_options_first()
    doc = "usage: prog [--opt] [<args>...]"

    @test docopt(doc, "--opt this that") ==
        {"--opt" => true, "<args>" => ["this", "that"]}
    @test docopt(doc, "this that --opt") ==
        {"--opt" => true, "<args>" => ["this", "that"]}
    @test docopt(doc, "this that --opt"; options_first=true) ==
        {"--opt" => false, "<args>" => ["this", "that", "--opt"]}
end

function test_issue_68_options_shortcut_does_not_include_options_in_usage_pattern()
    args = docopt("usage: prog [-ab] [options]\noptions: -x\n -y", "-ax")

    @test args["-a"] === true
    @test args["-b"] === false
    @test args["-x"] === true
    @test args["-y"] === false
end

function test_issue_65_evaluate_argv_when_called_not_when_imported()
    if !isempty(ARGS)
        throw(DomainError("ARGS should be empty"))
    end

    doc = "usage: prog [-ab]"
    push!(ARGS, "-a")
    @test docopt(doc) == {"-a" => true, "-b" => false}

    empty!(ARGS)
    push!(ARGS, "-b")
    @test docopt(doc) == {"-a" => false, "-b" => true}
end

function test_issue_71_double_dash_is_not_a_valid_option_argument()
    @test_throws DocOptExit docopt("usage: prog [--long=LEVEL] [--] <args>...", "--log -- 1 2"; exit_on_error=false)
    @test_throws DocOptExit docopt("""usage: prog [-l LEVEL] [--] <args>...
                                      options: -l LEVEL""", "-l -- 1 2"; exit_on_error=false)
end

usage = """usage: this

usage:hai
usage: this that

usage: foo
       bar

PROGRAM USAGE:
 foo
 bar
usage:
\ttoo
\ttar
Usage: eggs spam
BAZZ
usage: pit stop"""

function test_parse_section()
    parse_section = DocOpt.parse_section

    @test isempty(parse_section("usage:", "foo bar fizz buzz"))
    @test parse_section("usage:", "usage: prog") == ["usage: prog"]
    @test parse_section("usage:", "usage: -x\n -y") == ["usage: -x\n -y"]

    @test parse_section("usage:", usage)[1] == "usage: this"
    @test parse_section("usage:", usage)[2] == "usage:hai"
    @test parse_section("usage:", usage)[3] == "usage: this that"
    @test parse_section("usage:", usage)[4] == "usage: foo\n       bar"
    @test parse_section("usage:", usage)[5] == "PROGRAM USAGE:\n foo\n bar"
    #@show parse_section("usage:", usage)[6]  # julia expands tab characters (why?)
    #@test parse_section("usage:", usage)[6] == "usage:\n\ttoo\n\ttar"
    @test parse_section("usage:", usage)[7] == "Usage: eggs spam"
    @test parse_section("usage:", usage)[8] == "usage: pit stop"
end

test_pattern_flat()
test_option()
test_option_name()
test_commands()
test_formal_usage()
test_parse_argv()
test_parse_pattern()
test_option_match()
test_argument_match()
test_command_match()
test_optional_match()
test_required_match()
test_either_match()
test_one_or_more_match()
test_list_argument_match()
test_basic_pattern_matching()
test_pattern_either()
test_pattern_fix_repeating_arguments()
test_set()
test_pattern_fix_identities_1()
test_pattern_fix_identities_2()
test_long_options_error_handling()
test_short_options_error_handling()
test_matching_paren()
test_allow_double_dash()
test_docopt()
test_language_errors()
test_issue_40()
test_issue_34_unicode_strings()
test_any_options_parameter()
test_count_multiple_flags()
test_default_value_for_positional_arguments()
test_issue_59()
test_options_first()
test_issue_68_options_shortcut_does_not_include_options_in_usage_pattern()
test_issue_65_evaluate_argv_when_called_not_when_imported()
test_issue_71_double_dash_is_not_a_valid_option_argument()
test_parse_section()

end  # TestDocOpt
