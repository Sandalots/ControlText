:- dynamic object/2.

% Define objects in the game
object(keys, lobby).
object(service_weapon, directors_office).
object(janitor_cart, lobby).
object(health_pack, upper_hall).
object(artifact, directors_office).

% Define properties of objects
object_description(keys, "A set of old janitor's keys, rusty but functional.").
object_description(service_weapon, "A service weapon that feels powerful in your hands.").
object_description(janitor_cart, "A cart filled with cleaning supplies, abandoned in the lobby.").
object_description(health_pack, "A small health pack that can restore some health.").
object_description(artifact, "An unremarkable object that seems to hum with energy.").

% Rules for interacting with objects
take_item(Item) :-
    object(Item, Location),
    retract(object(Item, Location)),
    assert(has(jesse, Item)),
    format("You take the ~w.~n", [Item]),
    !.

take_item(_) :-
    writeln("You can't take that.").

drop_item(Item) :-
    has(jesse, Item),
    retract(has(jesse, Item)),
    assert(object(Item, lobby)), % Assuming dropped items go to the lobby
    format("You drop the ~w.~n", [Item]),
    !.

drop_item(_) :-
    writeln("You aren't holding that.").