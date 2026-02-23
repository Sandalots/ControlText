:- dynamic dialogue/2.

% Dialogue interactions with NPCs

% Ahti's dialogue
dialogue(ahti, greeting) :-
    writeln("'Welcome to the Bureau, Jesse. You look lost.'").

dialogue(ahti, keys_info) :-
    writeln("'Lost? Keys are in the lobby, my friend.'").

dialogue(ahti, after_keys) :-
    writeln("'Good. Keys open many doors.'").

% Generic responses
dialogue(npc, unknown) :-
    writeln("The character looks at you, confused."). 

% Function to initiate conversation
talk_to(NPC) :-
    location(jesse, Room),
    location(NPC, Room),
    (   has(jesse, keys)
    ->  dialogue(NPC, after_keys)
    ;   dialogue(NPC, greeting)
    ).

talk_to(NPC) :-
    writeln("You can't talk to that person right now.").