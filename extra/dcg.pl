% General shape:
% command(Action).
% command(Action, Object).
% command(Action, Object, Indirect).

% Examples:
% "go north"          -> command(go, north)
% "take keys"         -> command(take, keys)
% "look"              -> command(look)
% "look at cart"      -> command(look, cart)
% "talk to miller"    -> command(talk, miller)
% "stabilize mail room" -> command(stabilize, mail_room)

:- use_module(library(dcg/basics)).

% Entry point: parse a list of tokens into a Command term.
parse_command(Tokens, Command) :-
    phrase(command(Command), Tokens).

command(Command) -->
    verb_phrase(Command).

verb_phrase(command(Action)) -->
    verb(Action),
    eos.

verb_phrase(command(Action, Object)) -->
    verb(Action),
    object(Object),
    eos.

verb_phrase(command(Action, Object)) -->
    verb(Action),
    preposition(_),
    object(Object),
    eos.

verb_phrase(command(Action, Object, Indirect)) -->
    verb(Action),
    object(Object),
    preposition(_),
    object(Indirect),
    eos.

% End of sentence: no more tokens
eos --> [].

verb(go)    --> [go].
verb(go)    --> [walk].
verb(go)    --> [move].

verb(look)  --> [look].
verb(look)  --> [examine].
verb(look)  --> [inspect].

verb(take)  --> [take].
verb(take)  --> [grab].
verb(take)  --> [pick, up].

verb(talk)  --> [talk].
verb(talk)  --> [speak].

verb(stabilize) --> [stabilize].
verb(stabilize) --> [cleanse].
verb(stabilize) --> [clean].

verb(use)   --> [use].
verb(open)  --> [open].
verb(close) --> [close].

preposition(to)   --> [to].
preposition(at)   --> [at].
preposition(with) --> [with].
preposition(on)   --> [on].
preposition(in)   --> [in].

object(Object) -->
    object_tokens(Tokens),
    { normalise_object(Tokens, Object) }.

% One or more tokens until end-of-sentence
object_tokens([T|Ts]) --> [T], object_tokens_rest(Ts).

object_tokens_rest([T|Ts]) --> [T], object_tokens_rest(Ts).
object_tokens_rest([])     --> [].

% Map token lists to canonical object atoms

normalise_object([north], north).
normalise_object([south], south).
normalise_object([east],  east).
normalise_object([west],  west).

normalise_object([keys], keys).
normalise_object([key],  keys).

normalise_object([cart], cart).
normalise_object([janitor, cart], cart).

normalise_object([mail, room], mail_room).
normalise_object([security, checkpoint], security_checkpoint).
normalise_object([executive, hallway], executive_hallway).
normalise_object([directors, office], directors_office).
normalise_object([director, office], directors_office).

normalise_object([miller], agent_miller).
normalise_object([agent, miller], agent_miller).

normalise_object([lyra], researcher_lyra).
normalise_object([researcher, lyra], researcher_lyra).

% Fallback: join tokens with underscore
normalise_object(Tokens, Atom) :-
    atomic_list_concat(Tokens, '_', Atom).

?- parse_command([go, north], C).
C = command(go, north).

?- parse_command([take, keys], C).
C = command(take, keys).

?- parse_command([look, at, janitor, cart], C).
C = command(look, cart).

?- parse_command([talk, to, miller], C).
C = command(talk, agent_miller).

?- parse_command([stabilize, mail, room], C).
C = command(stabilize, mail_room).

?- parse_command([pick, up, keys], C).
C = command(take, keys).

game_loop :-
    repeat,
    read_line_to_string(user_input, line),
    string_lower(line, Lower),
    split_string(Lower, " ", " \t", Words),
    maplist(atom_string, Tokens, Words),
    (   parse_command(Tokens, Command)
    ->  handle_command(Command),
        (Command == command(quit) -> ! ; fail)
    ;   writeln("I don't understand that."),
        fail
    ).

handle_command(command(go, Dir)) :-
    perform(jesse, go(Dir)), !.

handle_command(command(look)) :-
    describe_current_location, !.

handle_command(command(look, Obj)) :-
    describe_object(Obj), !.

handle_command(command(take, Obj)) :-
    perform(jesse, take(Obj)), !.

handle_command(command(stabilize, Room)) :-
    perform(jesse, stabilize(Room)), !.

handle_command(Command) :-
    format("Command not implemented: ~w~n", [Command]).
