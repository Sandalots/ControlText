:- dynamic infected/1.
:- dynamic infection_level/2.

% Initial infection state
infected(jesse).
infection_level(jesse, 0).

% Rules for infection mechanics
contract_infection(Character) :-
    \+ infected(Character),
    assert(infected(Character)),
    writeln(Character), write(' has contracted the infection.'),
    update_infection_level(Character, 1).

contract_infection(Character) :-
    infected(Character),
    writeln(Character), write(' is already infected.').

update_infection_level(Character, Level) :-
    infection_level(Character, CurrentLevel),
    NewLevel is CurrentLevel + Level,
    retract(infection_level(Character, CurrentLevel)),
    assert(infection_level(Character, NewLevel)),
    format("~w's infection level is now ~w.~n", [Character, NewLevel]).

% Check for infection effects
check_infection(Character) :-
    infected(Character),
    infection_level(Character, Level),
    Level >= 5,
    writeln(Character), write(' is severely affected by the infection!'),
    % Additional effects can be added here
    !.

check_infection(Character) :-
    infected(Character),
    infection_level(Character, Level),
    Level < 5,
    writeln(Character), write(' shows mild symptoms of infection.').

check_infection(_) :-
    writeln('No infection detected.').