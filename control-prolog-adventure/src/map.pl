location(jesse, street).
building_shift(inactive).

description(street,
    "An empty New York street. The FBC building stands before you, humming faintly.").

connected(street, lobby, enter).

% Entering the building triggers a shift
perform(jesse, enter) :-
    location(jesse, street),
    retract(location(jesse, street)),
    assert(location(jesse, lobby)),
    assert(building_shift(active)).

description(lobby,
    "A vast lobby, impossibly large. A janitor's cart sits alone in the silence.").

connected(lobby, janitor_hall, east).
connected(janitor_hall, lobby, west).

connected(lobby, upper_hall, north) :-
    has(jesse, keys).        % locked until you get keys

connected(lobby, lobby, north) :-
    \+ has(jesse, keys).     % hallway loops until you get keys

connected(upper_hall, directors_office, north).
connected(directors_office, upper_hall, south).