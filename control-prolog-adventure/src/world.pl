:- dynamic location/2.
:- dynamic health/2.
:- dynamic has/2.

% Initial State
location(jesse, street).
health(jesse, 100).
has(jesse, none).

% Map Structure
connected(street, lobby, enter).
connected(lobby, street, exit).
connected(lobby, janitor_hall, east).
connected(janitor_hall, lobby, west).
connected(lobby, upper_hall, north) :- has(jesse, keys).
connected(upper_hall, directors_office, north).

% Room Descriptions
description(street, "An empty New York street. The FBC building stands before you, humming faintly.").
description(lobby, "A vast lobby, impossibly large. A janitor's cart sits alone in the silence.").
description(janitor_hall, "A narrow hallway. Ahti leans on his mop, watching you.").
description(upper_hall, "A long corridor. A Hiss-infected guard twitches violently.").
description(directors_office, "A quiet office. A pedestal holds an unremarkable service pistol.").

% Objects
object(keys, lobby).
object(service_weapon, directors_office).

% Game Lore
lore("The Federal Bureau of Control is a mysterious organization that investigates and contains supernatural phenomena.").
lore("The Oldest House, where the Bureau is located, is a place of shifting realities and strange occurrences.").

% Game Rules
can_move(Actor, Direction) :-
    location(Actor, CurrentRoom),
    connected(CurrentRoom, NextRoom, Direction),
    !.

can_move(_, _) :- fail.

% Describe the current location
describe_location :-
    location(jesse, Room),
    description(Room, Desc),
    writeln(Desc).

% List items and characters in the current location
list_occupants(Room) :-
    findall(N, (location(N, Room), N \= jesse), Others),
    (Others = [] -> true ; format("You see: ~w~n", [Others])).

list_items(Room) :-
    findall(I, object(I, Room), Items),
    (Items = [] -> true ; format("Items here: ~w~n", [Items])).