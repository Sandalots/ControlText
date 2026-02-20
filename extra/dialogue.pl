dialogue(agent_miller, clean, [
    line("Oh, thank god—someone from the outside."),
    line("Security systems are glitching. Be careful past the checkpoint.")
]).

dialogue(agent_miller, tainted, [
    line("…you hear it too, right? The humming."),
    line("Don’t stay long. It gets inside your thoughts.")
]).

dialogue(agent_miller, infected, [
    line("The song… the song is everything."),
    hostile
]).

dialogue(agent_miller, overrun, [
    hostile
]).

npc_dialogue(NPC, Lines) :-
    state(NPC, State),
    dialogue(NPC, State, Lines).

talk_to(NPC) :-
    npc_dialogue(NPC, Lines),
    play_lines(Lines).

play_lines([]).
play_lines([line(Text)|Rest]) :-
    writeln(Text),
    play_lines(Rest).

play_lines([hostile|_]) :-
    writeln("They lunge at you, eyes burning with resonance."),
    start_combat(NPC).



dialogue(researcher_lyra, clean, [
    line("You must be the new arrival. We need help stabilizing Parapsychology."),
    choice([
        option("What's happening here?", info),
        option("How do I stop the spread?", containment),
        option("I'll come back later.", exit)
    ])
]).

play_lines([choice(Options)|_]) :-
    show_options(Options),
    read(PlayerChoice),
    resolve_choice(PlayerChoice, Options).

show_options([]).
show_options([option(Text, _)|Rest]) :-
    writeln(Text),
    show_options(Rest).

resolve_choice(Input, [option(Text, Tag)|_]) :-
    Input = Text,
    handle_choice(Tag).

resolve_choice(Input, [_|Rest]) :-
    resolve_choice(Input, Rest).


handle_choice(info) :-
    writeln("Lyra explains the resonance anomalies spreading through the sector.").

handle_choice(containment) :-
    writeln("She tells you about a resonance node deeper inside Parapsychology.").

handle_choice(exit) :-
    writeln("Lyra nods and returns to her work.").

update_npc_infection(NPC) :-
    location(NPC, Room),
    state(Room, infected),
    escalate_npc(NPC).

escalate_npc(NPC) :-
    state(NPC, clean)    -> set_state(NPC, tainted)
 ;  state(NPC, tainted)  -> set_state(NPC, infected)
 ;  state(NPC, infected) -> set_state(NPC, overrun)
 ;  true.

set_state(NPC, New) :-
    retract(state(NPC, _)),
    assert(state(NPC, New)).
