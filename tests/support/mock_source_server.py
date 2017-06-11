#!/usr/bin/env python3
import sys
import time
from source_command_lang import parse_command, ParseException

MOCK_STEAMID = '[U:1:77263833]'
MOCK_IP = '223.5.114.232'

STATUS_TEMPLATE = """hostname: {hostname}
version : 3990974/24 3990974 secure
udp/ip  : 0.0.0.0:11111  (public ip: 111.23.46.1)
steamid : [A:1:1012065254:8265] (90119209251391411)
account : not logged in  (No account specified)
map     : {map} at: 0 x, 0 y, 0 z
tags    : cp,nocrits,ozfortress
sourcetv:  port 11111, delay 90.0s
players : {_player_count} humans, {_bot_count} bots ({_max_players} max)
edicts  : 193 used of 2048 max
         Spawns Points Kills Deaths Assists
Scout         0      0     0      0       0
Sniper       10      0     0      0       0
Soldier       1      3     1      1       1
Demoman       0      0     0      0       0
Medic         1      1     1      5       1
Heavy         0      0     0      0       0
Pyro         12      0     0      0       0
Spy           0      0     0      0       0
Engineer      0      0     0      0       0

# userid name                uniqueid            connected ping loss state  adr"""

BOT_LISTING = ""

STATUS_PLAYERS_PADDINGS = [6, 19, 19, 9, 4, 4, 5, 3]

class Server:
    DEFAULT_VARS = {
        'hostname': '0.0.0.0',
        'address': '0.0.0.0',
        'map': 'ctf_2fort',
        'sv_cheats': '0',
        'sv_password': '',
        'rcon_password': '',
        '_player_count': 0,
        '_bot_count': 1,
        '_max_players': 24,
    }

    COMMANDS = {
        'status': '_status',
        'quit': '_quit',
    }

    def __init__(self, args, input, output):
        self.input = input
        self.output = output

        self.variables = self.DEFAULT_VARS
        self.running = False

        self._parse_args(args)

    def _parse_args(self, args):
        args = args[:]

        while len(args) > 0:
            self._parse_arg(args)

    def _parse_arg(self, args):
        arg = args.pop(0)

        # Generically parse variables
        if arg[0] == '+':
            value = args.pop(0)
            self.variables[arg[1:]] = value

    def run(self):
        with self.output, self.input:
            self.running = True

            self.print('_STARTED')

            while self.running:
                line = self.input.readline()
                if line == '': break

                line = line[:-1]
                self.run_command(line)

            self.print('_STOPPED')

    def run_command(self, command):
        try:
            commands = parse_command(command)
        except ParseException:
            self.print('Invalid command "{}"'.format(command))
            return

        for args in commands:
            command = args[0]
            args = args[1:]

            if command in self.COMMANDS:
                getattr(self, self.COMMANDS[command])(args)
            elif command in self.variables:
                if len(args) == 0:
                    self.output_var(command)
                else:
                    self.variables[command] = ' '.join(args)
            else:
                self.print('Unknown command "{}"'.format(command))

    def print(self, *args, **kwargs):
        kwargs['file'] = self.output
        print(*args, **kwargs)

    def output_var(self, name):
        self.print(name)
        self.print('"{}" = "{}"'.format(name, self.variables[name]))
        self.print(' - some description of the variable')

    def _status(self, args):
        self.print('status')

        vars = {**self.__dict__, **self.variables}
        self.print(STATUS_TEMPLATE.format(**vars))

        id = 1

        # Bots
        for index in range(int(self.variables['_bot_count'])):
            items = [id, '"bot{}"'.format(index), 'BOT', '', '', '', 'active', '']
            self._status_player(items)
            id += 1

        # Players
        for index in range(int(self.variables['_player_count'])):
            items = [id, '"player{}"'.format(index), MOCK_STEAMID, '11:21', 19, 0, 'active', MOCK_IP]
            self._status_player(items)
            id += 1

    def _status_player(self, items):
        for i in range(len(items)):
            padding = STATUS_PLAYERS_PADDINGS[i]

            if isinstance(items[i], int):
                items[i] = str(items[i]).rjust(padding)
            else:
                items[i] = items[i].ljust(padding)

        self.print('# {}'.format(' '.join(items)))

    def _quit(self, args):
        self.print('quit')
        self.running = False

def main(args):
    server = Server(args[1:], sys.stdin, sys.stdout)

    server.run()

if __name__ == '__main__':
    main(sys.argv)
