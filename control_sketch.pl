% Initial state
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

