                [Director’s Office]
                        |
                [Executive Hallway]
                        |
[Lobby] --- [Security Checkpoint] --- [Mail Room]
                        |
                 [Research Access]
                        |
                 [Parapsychology]

connected(lobby, executive_hallway, north) :-
    hallway_stable(true).

connected(lobby, lobby, north) :-
    hallway_stable(false).

connected(mail_room, parapsychology, east) :-
    building_shift(active).

connected(mail_room, security_checkpoint, west) :-
    building_shift(inactive).

connected(security_checkpoint, research_access, south) :-
    has_clearance(jesse, level2).

connected(security_checkpoint, research_access, south) :-
    has(jesse, floppy_disk).

story_event(bind_weapon) :-
    location(jesse, directors_office),
    not(has(jesse, service_weapon)).

perform(jesse, activate(node)) :-
    location(jesse, parapsychology),
    retract(building_shift(active)),
    assert(building_shift(inactive)).
