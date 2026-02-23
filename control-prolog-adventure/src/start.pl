:- dynamic i_am_at/1, at/2, holding/1.
:- retractall(at(_, _)), retractall(i_am_at(_)).

i_am_at(street).

path(street, enter, lobby).

at(keys, lobby).

start :-
    writeln("Welcome to the Control-inspired text adventure!"),
    writeln("You find yourself standing outside the Federal Bureau of Control."),
    writeln("The building looms above you, humming with a strange resonance."),
    writeln("Something pulls you toward the entrance."),
    writeln(""),
    writeln("Tip: try 'enter' to go inside."),
    writeln(""),
    look.

look :-
    i_am_at(Place),
    describe(Place),
    nl,
    notice_objects_at(Place),
    nl.

describe(street) :-
    writeln("You are on an empty New York street. The FBC building stands before you, humming faintly.").

notice_objects_at(Place) :-
    at(X, Place),
    format("There is a ~w here.~n", [X]),
    fail.

notice_objects_at(_).