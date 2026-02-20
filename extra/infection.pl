infected(lobby, false).
infected(security_checkpoint, false).
infected(mail_room, false).
infected(executive_hallway, false).
infected(directors_office, false).
infected(research_access, false).
infected(parapsychology, false).

npc(agent_miller).
npc(researcher_lyra).

infected(agent_miller, false).
infected(researcher_lyra, false).

spread_hiss(Room) :-
    adjacent(Room, R2),
    infected(R2, true),
    not(sealed(Room)),
    retract(infected(Room, false)),
    assert(infected(Room, true)).

spread_hiss_to_npc(NPC) :-
    location(NPC, Room),
    infected(Room, true),
    retract(infected(NPC, false)),
    assert(infected(NPC, true)).

hiss_pulse :-
    findall(R, infected(R, true), Rooms),
    length(Rooms, N),
    N >= 3.

perform(jesse, stabilize(Room)) :-
    has(jesse, service_weapon),
    retract(sealed(Room)),
    assert(sealed(Room)).

spread_hiss(Room) :-
    sealed(Room),
    !, fail.

description(Room, Desc) :-
    infected(Room, true),
    infected_description(Room, Desc).

description(Room, Desc) :-
    infected(Room, false),
    normal_description(Room, Desc).

npc_behavior(NPC, hostile) :-
    infected(NPC, true).

npc_behavior(NPC, friendly) :-
    infected(NPC, false).

spread_hiss(executive_hallway) :-
    assert(building_shift(active)).
