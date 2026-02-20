location(jesse, lobby).
has(jesse, none).

building_mood(neutral).
hallway_exists(false).
ahti_visible(false).

description(lobby, 
"An impossibly large lobby with a janitor's cart and flickering lights. 
A rhythmic sound echoes from above.").

object(cart, lobby).
object(keys, cart).

perform(jesse, take(keys)) :-
    location(jesse, lobby),
    object(keys, cart),
    retract(object(keys, cart)),
    assert(has(jesse, keys)),
    shift_building.

shift_building :-
    retract(building_mood(neutral)),
    assert(building_mood(attentive)),
    assert(hallway_exists(true)),
    assert(ahti_visible(true)).

description(ahti, 
"A calm janitor with knowing eyes. He gestures toward a newly formed hallway.").

npc(ahti) :- ahti_visible(true).

connected(lobby, hallway, north) :- hallway_exists(true).

description(hallway,
"A narrow corridor that wasn't here moments ago. 
The air feels charged, as if the building is watching.").

perform(jesse, go(north)) :-
    location(jesse, lobby),
    hallway_exists(true),
    (   has(jesse, keys)
    ->  retract(location(jesse, lobby)),
        assert(location(jesse, corridor))
    ;   true  % stays in lobby
    ).

story_event(meet_pope) :-
    location(jesse, corridor),
    building_mood(attentive).
