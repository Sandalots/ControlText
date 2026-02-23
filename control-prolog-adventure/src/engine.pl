:- dynamic i_am_at/1, at/2, holding/1.
:- retractall(at(_, _)), retractall(i_am_at(_)).

i_am_at(street).

path(street, enter, lobby).

at(keys, lobby).
at(service_weapon, directors_office).

take(X) :-
    holding(X),
    write('You''re already holding it!'),
    !, nl.

take(X) :-
    i_am_at(Place),
    at(X, Place),
    retract(at(X, Place)),
    assert(holding(X)),
    write('You picked up the '), write(X), write('.'), nl,
    !.

take(_) :-
    write('I don''t see it here.'), nl.

drop(X) :-
    holding(X),
    i_am_at(Place),
    retract(holding(X)),
    assert(at(X, Place)),
    write('You dropped the '), write(X), write('.'), nl,
    !.

drop(_) :-
    write('You aren''t holding it!'), nl.

n :- go(n).
s :- go(s).
e :- go(e).
w :- go(w).

go(Direction) :-
    i_am_at(Here),
    path(Here, Direction, There),
    retract(i_am_at(Here)),
    assert(i_am_at(There)),
    !, look.

go(_) :-
    write('You can''t go that way.').

look :-
    i_am_at(Place),
    describe(Place),
    nl,
    notice_objects_at(Place),
    nl.

notice_objects_at(Place) :-
    at(X, Place),
    write('There is a '), write(X), write(' here.'), nl,
    fail.

notice_objects_at(_).

die :-
    finish.

finish :-
    nl,
    write('The game is over. Please enter the "halt." command.'),
    nl.

instructions :-
    nl,
    write('Enter commands using standard Prolog syntax.'), nl,
    write('Available commands are:'), nl,
    write('start.             -- to start the game.'), nl,
    write('n.  s.  e.  w.     -- to go in that direction.'), nl,
    write('take(Object).      -- to pick up an object.'), nl,
    write('drop(Object).      -- to put down an object.'), nl,
    write('look.              -- to look around you again.'), nl,
    write('instructions.      -- to see this message again.'), nl,
    write('halt.              -- to end the game and quit.'), nl,
    nl.

start :-
    instructions,
    look.

describe(street) :- write('You stand outside the Federal Bureau of Control. The building looms above you, humming with a strange, low resonance.'), nl.
describe(lobby) :- write('A vast lobby, impossibly large. A janitor''s cart sits alone in the silence.'), nl.
describe(directors_office) :- write('A quiet office. A pedestal holds an unremarkable service pistol.'), nl.