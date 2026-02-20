:- module(engine, [start/0]).
:- use_module('./parser.pl').
:- use_module('./world.pl').
:- use_module('./map.pl').
:- use_module('./infection.pl').
:- use_module('./dialogue.pl').
:- use_module('./combat.pl').
:- use_module('./objects.pl').

start :-
    writeln("The Oldest House hums quietly."),
    describe_here,
    game_loop.

game_loop :-
    repeat,
    write("> "),
    read_line_to_string(user_input, Line),
    string_lower(Line, Lower),
    split_string(Lower, " ", " \t", Words),
    maplist(atom_string, Tokens, Words),
    (   parse_command(Tokens, Command)
    ->  update_world,
        dispatch(Command),
        (Command = command(quit) -> ! ; fail)
    ;   writeln("I don't understand that."),
        fail
    ).

dispatch(command(quit)) :-
    writeln("You let the building keep its secrets. For now.").

dispatch(command(look)) :-
    describe_here.

dispatch(command(go, Dir)) :-
    move(jesse, Dir).

dispatch(command(talk, NPC)) :-
    talk_to(NPC).

dispatch(command(attack, Target)) :-
    combat_turn(jesse, Target).

dispatch(command(take, Obj)) :-
    perform(jesse, take(Obj)).

dispatch(command(look, Obj)) :-
    format("You look at ~w.~n", [Obj]).

dispatch(C) :-
    format("Command not implemented: ~w~n", [C]).
