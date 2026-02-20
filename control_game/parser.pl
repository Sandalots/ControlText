:- module(parser, [parse_command/2]).
:- use_module(library(dcg/basics)).

parse_command(Tokens, Command) :-
    phrase(command(Command), Tokens).

command(Cmd) --> verb_phrase(Cmd), [].

verb_phrase(command(go, Dir)) --> verb(go), object(Dir).
verb_phrase(command(look)) --> verb(look).
verb_phrase(command(look, Obj)) --> verb(look), object(Obj).
verb_phrase(command(take, Obj)) --> verb(take), object(Obj).
verb_phrase(command(talk, NPC)) --> verb(talk), object(NPC).
verb_phrase(command(attack, Target)) --> [attack], object(Target).
verb_phrase(command(quit)) --> [quit].

verb(go) --> [go] | [walk] | [move].
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
normalise_object([east], east).
normalise_object([west], west).
normalise_object([miller], agent_miller).
normalise_object(Toks, Atom) :-
    atomic_list_concat(Toks, '_', Atom).
