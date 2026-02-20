:- module(dialogue, [talk_to/1]).
:- use_module(infection).

dialogue(agent_miller, clean, [
    "Oh, thank god—someone made it through.",
    "Security's failing. Don't trust the quiet rooms."
]).

dialogue(agent_miller, tainted, [
    "…you hear it too, right? The humming.",
    "Don't stay long. It gets inside your thoughts."
]).

dialogue(agent_miller, infected, [
    "The song… the song is everything.",
    hostile
]).

talk_to(NPC) :-
    state(NPC, State),
    dialogue(NPC, State, Lines),
    play_lines(NPC, Lines).

play_lines(_, []).
play_lines(NPC, [hostile|_]) :-
    writeln("They lunge at you, eyes burning with resonance."),
    start_combat(NPC).
play_lines(NPC, [line(Text)|Rest]) :-
    writeln(Text),
    play_lines(NPC, Rest).
play_lines(NPC, [Text|Rest]) :-
    writeln(Text),
    play_lines(NPC, Rest).
