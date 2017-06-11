from pyparsing import Group, Word, ZeroOrMore, Optional, Suppress, QuotedString, alphanums, printables
from pyparsing import ParseException

TERMINATOR = Suppress(';')
IDENTIFIER = Word(alphanums + '_')
STRING = QuotedString('"', '\\', convertWhitespaceEscapes=False)
COMMAND = Group(IDENTIFIER + ZeroOrMore(IDENTIFIER | STRING))
LANGUAGE = COMMAND + ZeroOrMore(TERMINATOR + COMMAND) + Optional(TERMINATOR)

def parse_command(command):
    return LANGUAGE.parseString(command, parseAll=True).asList()

def test_parse_command():
    assert parse_command('sv_cheats 1') == [['sv_cheats', '1']]

    assert parse_command('sv_cheats 1;') == [['sv_cheats', '1']]

    assert parse_command('sv_cheats "1"') == [['sv_cheats', '1']]

    assert parse_command('command "arg1"  "  " foobar foo') == [['command', 'arg1', '  ', 'foobar', 'foo']]

    assert parse_command('sv 1; sv 2; sv3') == [['sv', '1'], ['sv', '2'], ['sv3']]

    assert parse_command('sv 1; sv 2; sv3;') == [['sv', '1'], ['sv', '2',], ['sv3']]

