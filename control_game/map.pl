:- module(map, [connected/3, description/2]).

connected(lobby, security_checkpoint, east).
connected(security_checkpoint, lobby, west).

normal_description(lobby,
"An impossibly large lobby with a reception desk and a janitor's cart.").

normal_description(security_checkpoint,
"A security checkpoint with flickering monitors and an uneasy silence.").

description(Room, Desc) :-
    normal_description(Room, Desc).
