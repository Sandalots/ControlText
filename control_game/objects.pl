:- module(objects, [perform/2]).
:- dynamic has/2.

perform(jesse, take(keys)) :-
    writeln("You pick up the keys."),
    retract(has(jesse, none)),
    assert(has(jesse, keys)).
perform(_, _) :-
    writeln("You can't do that.").
