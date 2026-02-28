/* ============================================
      CONTROL‑STYLE TEXT ADVENTURE (SIMPLE+)
      Single‑file version with:
      - 5 rooms
      - Ahti NPC
      - Hiss guard enemy
      - A key puzzle
      - Simple parser
   ============================================ */

:- dynamic location/2.
:- dynamic health/2.
:- dynamic has/2.

/* --- Initial State --- */

location(jesse, street).
location(ahti, janitor_hall).
location(hiss_guard, upper_hall).

health(jesse, 100).
health(hiss_guard, 30).

has(jesse, none).

/* --- Map --- */

connected(street, lobby, enter).
connected(lobby, street, exit).   % optional, but fun

connected(lobby, janitor_hall, east).
connected(janitor_hall, lobby, west).

connected(lobby, upper_hall, north) :-
    has(jesse, keys).        % locked until you get keys

connected(lobby, lobby, north) :-
    \+ has(jesse, keys).     % hallway loops until you get keys

connected(upper_hall, directors_office, north).
connected(directors_office, upper_hall, south).

/* --- Room Descriptions --- */

description(street,
"You stand outside the Federal Bureau of Control. The building is tall, \
featureless, and humming faintly. The front doors wait silently.").


description(lobby,
"A vast lobby with humming lights. A janitor's cart sits alone.").

description(janitor_hall,
"A narrow hallway. Ahti leans on his mop, watching you.").

description(upper_hall,
"A long corridor. A Hiss‑infected guard twitches violently.").

description(directors_office,
"A quiet office. A pedestal holds an unremarkable service pistol.").

/* --- Items --- */

object(keys, lobby).
object(service_weapon, directors_office).

/* --- Game Start --- */

start :-
    writeln("You arrive at the Federal Bureau of Control."),
    writeln("The building looms above you, humming with a strange, low resonance."),
    writeln("Something pulls you toward the entrance."),
    writeln(""),
    writeln("Tip: try 'enter' to go inside."),
    writeln(""),
    describe_here,
    game_loop.

/* --- Game Loop --- */

game_loop :-
    repeat,
    write("> "),
    read_line_to_string(user_input, Line),
    string_lower(Line, Lower),
    split_string(Lower, " ", " \t", Words),
    maplist(atom_string, Tokens, Words),
    (   parse(Tokens, Command)
    ->  dispatch(Command),
        (Command = quit -> ! ; fail)
    ;   writeln("I don't understand."),
        fail
    ).

/* --- Parser --- */

parse([go, Dir], go(Dir)).
parse([move, Dir], go(Dir)).
parse([walk, Dir], go(Dir)).

parse([look], look).
parse([look, at, Obj], look_at(Obj)).

parse([take, Obj], take(Obj)).
parse([pick, up, Obj], take(Obj)).

parse([talk, ahti], talk(ahti)).
parse([attack, hiss_guard], attack(hiss_guard)).

parse([quit], quit).

parse([help], help).

parse([enter], go(enter)).
parse([go, inside], go(enter)).
parse([go, in], go(enter)).



/* --- Command Dispatch --- */

dispatch(look) :- describe_here.
dispatch(look_at(Obj)) :- look_at(Obj).
dispatch(go(Dir)) :- move(jesse, Dir).
dispatch(talk(ahti)) :- talk_to(ahti).
dispatch(take(Obj)) :- take_item(Obj).
dispatch(attack(hiss_guard)) :- combat(jesse, hiss_guard).
dispatch(quit) :- writeln("You step back from the House.").
dispatch(help) :- show_help.


dispatch(Cmd) :-
    format("I don't know how to handle: ~w~n", [Cmd]).


/* --- Tutorial Text --- */
show_help :-
    writeln("=== COMMANDS ==="),
    writeln("Movement: go north | go south | go east | go west"),
    writeln("Look:     look | look at <thing>"),
    writeln("Items:    take <item>"),
    writeln("Talk:     talk <npc>"),
    writeln("Combat:   attack <enemy>"),
    writeln("Quit:     quit"),
    writeln("================").

/* Funny Text */
funny_outside_message :-
    outside_attempts(N),
    N1 is N + 1,
    retract(outside_attempts(N)),
    assert(outside_attempts(N1)),
    outside_message(N1).

outside_message(1) :-
    writeln("You take a few steps away… then stop. Something feels wrong."),
    writeln("The building hums louder, like it's watching you.").

outside_message(2) :-
    writeln("You try to walk off, but your feet feel heavy."),
    writeln("Almost like the building is disappointed in you.").

outside_message(3) :-
    writeln("You turn around again. The Bureau is still there."),
    writeln("It feels… expectant. Maybe go inside?").

outside_message(4) :-
    writeln("You walk in a circle. The street loops."),
    writeln("Okay, the House is definitely messing with you now.").

outside_message(_) :-
    writeln("You cannot escape the Oldest House. Just go inside.").

:- dynamic outside_attempts/1.
outside_attempts(0).

/* --- Movement --- */
move(jesse, Dir) :-
    location(jesse, street),
    Dir \= enter,
    funny_outside_message,
    !.

move(Actor, Dir) :-
    location(Actor, Room),
    (   connected(Room, Next, Dir)
    ->  retract(location(Actor, Room)),
        assert(location(Actor, Next)),
        describe_here
    ;   writeln("You can't go that way.")
    ).

/* --- Descriptions --- */

% New: centered ASCII map showing only adjacent N/S/E/W rooms and locked status.
map_label_center(Room, Label) :-
    format(atom(Label), "[>~w<]", [Room]).

label_with_status(Name, Status, Label) :-
    ( Status = locked
    -> format(atom(Label), "[~w] (locked)", [Name])
    ;  format(atom(Label), "[~w]", [Name])
    ).

% treat alternate connection atoms as cardinals
dir_equiv(north, north).
dir_equiv(north, enter).
dir_equiv(south, south).
dir_equiv(south, exit).
dir_equiv(east,  east).
dir_equiv(west,  west).

% neighbor/4: succeed if there's an effective neighbor in Dir (now using dir_equiv/2).
neighbor(Current, Cardinal, DisplayNext, Status) :-
    dir_equiv(Cardinal, ConnDir),
    ( connected(Current, Next, ConnDir) ->
        ( Next \= Current
        -> DisplayNext = Next, Status = open
        ;  % Next == Current: check if an alternate clause exists (locked)
           ( clause(connected(Current, Alt, ConnDir), _) , Alt \= Current
           -> DisplayNext = Alt, Status = locked
           ;  % genuine self-loop -> treat as no neighbor
              fail
           )
        )
    ;  % no direct success: maybe there's a conditional clause that would allow movement (locked)
       ( clause(connected(Current, Alt, ConnDir), _) ->
           DisplayNext = Alt, Status = locked
       ; fail )
    ).

show_map(Current) :-
    map_label_center(Current, Center),

    ( neighbor(Current, north, N, NStatus) -> label_with_status(N, NStatus, NLabel) ; NLabel = "" ),
    ( neighbor(Current, south, S, SStatus) -> label_with_status(S, SStatus, SLabel) ; SLabel = "" ),
    ( neighbor(Current, east,  E, EStatus)  -> label_with_status(E, EStatus, ELabel) ; ELabel = "" ),
    ( neighbor(Current, west,  W, WStatus)  -> label_with_status(W, WStatus, WLabel) ; WLabel = "" ),

    writeln(""),
    writeln("Map:"),

    % North (centered above)
    ( NLabel \= "" -> format("      ~w~n      ^~n", [NLabel]) ; true ),

    % Middle: west - center - east (with arrowheads)
    ( WLabel \= "", ELabel \= "" ->
        format("~w <-- ~w --> ~w~n", [WLabel, Center, ELabel])
    ; WLabel \= "" ->
        format("~w <-- ~w~n", [WLabel, Center])
    ; ELabel \= "" ->
        format("      ~w --> ~w~n", [Center, ELabel])
    ;  % no lateral neighbors: just show center (centered)
       format("      ~w~n", [Center])
    ),

    % South (centered below)
    ( SLabel \= "" -> format("      v~n      ~w~n", [SLabel]) ; true ),

    writeln("").

