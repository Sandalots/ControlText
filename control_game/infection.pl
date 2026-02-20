:- module(infection, [
    update_world/0,
    state/2,
    sealed/1
]).

:- dynamic state/2.
:- dynamic sealed/1.

state(lobby, clean).
state(security_checkpoint, tainted).

update_world :-
    propagate_all_rooms,
    propagate_all_npcs,
    maybe_pulse.

propagate_all_rooms :-
    forall(state(Room, _), try_propagate_room(Room)).

propagate_all_npcs :-
    forall(npc(N), try_propagate_npc(N)).

try_propagate_room(Room) :-
    state(Room, tainted),
    retract(state(Room, tainted)),
    assert(state(Room, infected)), !.
try_propagate_room(_).

try_propagate_npc(NPC) :-
    state(NPC, clean),
    location(NPC, Room),
    state(Room, infected),
    retract(state(NPC, clean)),
    assert(state(NPC, tainted)), !.
try_propagate_npc(_).

maybe_pulse :-
    findall(R, state(R, infected), L),
    length(L, N),
    (N >= 2 -> writeln("A low resonance pulse rolls through the building.") ; true).
