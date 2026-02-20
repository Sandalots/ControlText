:- dynamic location/2.
:- dynamic health/2.
:- dynamic resonance/2.
:- dynamic has/2.
:- dynamic state/2.
:- dynamic sealed/1.
:- dynamic current_mode/1.

% Initial state
location(jesse, lobby).
health(jesse, 100).
resonance(jesse, 30).
has(jesse, none).
current_mode(grip).

% Example enemy
enemy(hiss_guard).
location(hiss_guard, security_checkpoint).
health(hiss_guard, 40).
state(hiss_guard, infected).

% Example NPC
npc(agent_miller).
location(agent_miller, security_checkpoint).
state(agent_miller, clean).

connected(lobby, security_checkpoint, east).
connected(security_checkpoint, lobby, west).

normal_description(lobby,
"An impossibly large lobby with a reception desk and a janitor's cart.").

normal_description(security_checkpoint,
"A security checkpoint with flickering monitors and an uneasy silence.").

description(Room, Desc) :-
    normal_description(Room, Desc).

parse_command(Tokens, Command) :-
    phrase(command(Command), Tokens).

command(Cmd) --> verb_phrase(Cmd), [].

verb_phrase(command(go, Dir)) --> verb(go), object(Dir).
verb_phrase(command(look))    --> verb(look).
verb_phrase(command(look, Obj)) --> verb(look), object(Obj).
verb_phrase(command(take, Obj)) --> verb(take), object(Obj).
verb_phrase(command(talk, NPC)) --> verb(talk), object(NPC).
verb_phrase(command(attack, Target)) --> [attack], object(Target).
verb_phrase(command(quit)) --> [quit].

verb(go)   --> [go] | [walk] | [move].
verb(look) --> [look] | [examine].
verb(take) --> [take] | [grab].
verb(talk) --> [talk] | [speak].

object(Obj) -->
    object_tokens(Toks),
    { normalise_object(Toks, Obj) }.

object_tokens([T|Ts]) --> [T], object_tokens_rest(Ts).
object_tokens_rest([T|Ts]) --> [T], object_tokens_rest(Ts).
object_tokens_rest([]) --> [].

normalise_object([north], north).
normalise_object([south], south).
normalise_object([east],  east).
normalise_object([west],  west).
normalise_object([miller], agent_miller).
normalise_object(Toks, Atom) :- atomic_list_concat(Toks, '_', Atom).

start :-
    writeln("The Oldest House hums quietly."),
    describe_here,
    game_loop.

game_loop :-
    repeat,
    write("> "),
    read_line_to_string(user_input, line),
    string_lower(line, Lower),
    split_string(Lower, " ", " \t", Words),
    maplist(atom_string, Tokens, Words),
    (   parse_command(Tokens, Command)
    ->  ( handle_command(Command),
          (Command = command(quit) -> ! ; fail)
        )
    ;   writeln("I don't understand that."), fail
    ).

handle_command(command(quit)) :-
    writeln("You let the building keep its secrets. For now.").

handle_command(command(look)) :-
    describe_here.

handle_command(command(go, Dir)) :-
    move(jesse, Dir).

handle_command(command(take, Obj)) :-
    perform(jesse, take(Obj)).

handle_command(command(talk, NPC)) :-
    talk_to(NPC).

handle_command(command(attack, Target)) :-
    combat_turn(jesse, Target).

handle_command(command(look, Obj)) :-
    format("You look at ~w.~n", [Obj]).

handle_command(C) :-
    format("Command not implemented: ~w~n", [C]).

move(Actor, Dir) :-
    location(Actor, Room),
    (   exit_to(Room, Dir, Next)
    ->  retract(location(Actor, Room)),
        assert(location(Actor, Next)),
        describe_here
    ;   writeln("You can't go that way.")
    ).

exit_to(Room, east, Next)  :- connected(Room, Next, east).
exit_to(Room, west, Next)  :- connected(Room, Next, west).
exit_to(Room, north, Next) :- connected(Room, Next, north).
exit_to(Room, south, Next) :- connected(Room, Next, south).

describe_here :-
    location(jesse, Room),
    description(Room, Desc),
    writeln(Desc),
    list_occupants(Room).

list_occupants(Room) :-
    findall(N, (npc(N), location(N, Room)), NPCs),
    findall(E, (enemy(E), location(E, Room)), Enemies),
    (NPCs \= [] -> format("You see: ~w~n", [NPCs]) ; true),
    (Enemies \= [] -> format("Hostiles present: ~w~n", [Enemies]) ; true).

dialogue(agent_miller, clean, [
    "Oh, thank god—someone made it through.",
    "Security's failing. Don't trust the quiet rooms."
]).

dialogue(agent_miller, infected, [
    "The song… the song is everything."
]).

talk_to(NPC) :-
    npc(NPC),
    state(NPC, State),
    dialogue(NPC, State, Lines),
    forall(member(L, Lines), writeln(L)),
    (State = infected -> start_combat(NPC) ; true).

start_combat(NPC) :-
    format("~w turns hostile!~n", [NPC]).

dialogue(agent_miller, clean, [
    "Oh, thank god—someone made it through.",
    "Security's failing. Don't trust the quiet rooms."
]).

dialogue(agent_miller, infected, [
    "The song… the song is everything."
]).

talk_to(NPC) :-
    npc(NPC),
    state(NPC, State),
    dialogue(NPC, State, Lines),
    forall(member(L, Lines), writeln(L)),
    (State = infected -> start_combat(NPC) ; true).

start_combat(NPC) :-
    format("~w turns hostile!~n", [NPC]).
