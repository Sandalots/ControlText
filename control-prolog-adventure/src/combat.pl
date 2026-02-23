:- dynamic health/2.
:- dynamic location/2.
:- dynamic holding/1.

% Initial health points for characters
health(jesse, 100).
health(hiss_guard, 30).

% Combat mechanics
combat(jesse, hiss_guard) :-
    location(jesse, upper_hall),
    health(hiss_guard, HP),
    HP > 0,
    writeln("You fire at the Hiss Guard."),
    NewHP is HP - 12,
    retract(health(hiss_guard, HP)),
    assert(health(hiss_guard, NewHP)),
    format("Hiss Guard now has ~w HP.~n", [NewHP]),
    enemy_turn, !.

combat(_, hiss_guard) :-
    writeln("There's nothing to attack here."), !.

% Enemy turn mechanics
enemy_turn :-
    health(hiss_guard, HP),
    HP =< 0,
    writeln("The Hiss Guard collapses into silence."), !.

enemy_turn :-
    writeln("The Hiss Guard lashes out!"),
    health(jesse, JHP),
    NewJHP is JHP - 8,
    retract(health(jesse, JHP)),
    assert(health(jesse, NewJHP)),
    format("You now have ~w HP.~n", [NewJHP]),
    (NewJHP =< 0 -> die ; true).

% Rule for dying
die :-
    writeln("You have been defeated. Game over."),
    halt.