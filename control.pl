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
:- dynamic read_note/2.          % store room–noteid pairs already read
:- use_module(library(pcre)).        % for re_replace/4
:- use_module(library(ansi_term)).   % for colour output

/* --- Helpers --- */

% strip non‑letters from the beginning/end of a word so "enter." → "enter"
clean_token(In, Out) :-
    re_replace('(^[^a-z]+|[^a-z]+$)'/i, '', In, Out).

% colourised output helpers
color_ln(Color, Text) :-
    ansi_format([fg(Color)], '~w~n', [Text]).
normal_text(Text)    :- color_ln(green,  Text).
highlight_text(Text) :- color_ln(yellow, Text).
map_text(Text)       :- color_ln(cyan,   Text).
tip_text(Text)       :- ansi_format([fg(magenta), bold], '~w~n', [Text]).  % new

% speak(Character,Text) – choose a colour for the speaker and print in
% italic.  previously used green/yellow; switch to red.
speak(ahti, Text)   :- ansi_format([fg(red), italic], '~w~n', [Text]).
speak(vendor, Text) :- ansi_format([fg(red), italic], '~w~n', [Text]).
speak(_, Text)      :- normal_text(Text).   % fallback

/* --- Initial State --- */

location(jesse, street).
location(ahti, janitor_hall).
location(hiss_guard, upper_hall).
location(vendor, food_vendor).

health(jesse, 100).
health(hiss_guard, 30).

/* --- Map --- */

connected(street, lobby, enter).
connected(lobby, street, exit).

connected(street, food_vendor, east).        % hot‑dog vendor
connected(food_vendor, street, west).

connected(street, west_road, west).         % was north
connected(west_road, street, east).         % was south

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

description(food_vendor,
"A greasy hot‑dog cart stands here. A man in a stained apron shouts, \
'Best dogs in the Oldest House!'").

description(west_road,
"A quiet side street veering north. The air smells like dust and old paper. There's not much here.").

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

/* --- Notes --- */
% note(Room, Id, Text).
note(street, welcome,
    "A faded government memo: 'The Bureau never sleeps. Neither should you.'").
note(street, construction,
    "Public Notice: There will be noisy construction in this area for some time. \
We thank you for your cooperation and patience during these improvements.").
note(lobby, janitor,
    "Scrawled on the janitor's cart: 'Keys open doors; doors open minds.'").
note(lobby, security_bulletin,
    "Security Bulletin: If you witness levitation, remain calm and alert a supervisor. \
Do not engage unless properly trained.").
note(lobby, visitor_policy,
    "Visitor Policy: Unscheduled guests must wait in the lobby for escort. \
Please keep your ID visible at all times.").
note(lobby, missing_file,
    "Typed memo with coffee rings: 'Case file 11-07 has gone missing again. \
If found humming, do not open it.'").
note(lobby, overtime_notice,
    "Notice to Staff: Overtime this week is mandatory. \
The House has been shifting after hours.").

note(west_road, old_sign,
    "A weathered street sign, half-obscured by vines: 'Dimensional Research Wing - 2 miles.'").

note(west_road, graffiti,
    "Cryptic graffiti scratched into a brick wall: 'The House changes. Don't let it change you.'").

note(west_road, lost_time,
    "A discarded pocket watch lies in the dirt. The hands spin wildly, unable to settle on a time.").

% when you enter or start, tell player if there are unread notes
list_notes(Room) :-
    findall(Id, (note(Room,Id,_), \+ read_note(Room,Id)), Unread),
    ( Unread = [] -> true
    ; atomic_list_concat(Unread, ', ', IdStr),
      format(string(S),
             "Unread notes here: ~w. Use 'read <name>' to examine one.",
             [IdStr]),
      highlight_text(S)
    ).

% read all notes in current location, mark them as read
read_notes(all) :-
    location(jesse, Room),
    findall(Id-Text, (note(Room,Id,Text), \+ read_note(Room,Id)), Pairs),
    ( Pairs = [] ->
        color_ln(red, "There's nothing to read here.")
    ; forall(member(Id-Text, Pairs),
             ( color_ln(red, Text),
               assertz(read_note(Room,Id))
             ))
    ).

% read a single named note
read_notes(Name) :-
    location(jesse, Room),
    ( note(Room, Name, Text) ->
        ( read_note(Room, Name) ->
            color_ln(red, "You've already read that.")
        ; color_ln(red, Text),
          assertz(read_note(Room, Name))
        )
    ; color_ln(red, "No such note here.")
    ).

/* --- Dialogue --- */

talk_to(ahti) :-
    location(jesse, janitor_hall),
    (   has(jesse, keys)
    ->  speak(ahti, "'Good. Keys open many doors,' Ahti says with a grin.")
    ;   speak(ahti, "'Lost? Keys are in the lobby,' Ahti says, pointing back.")
    ), !.

talk_to(vendor) :-
    location(jesse, food_vendor),
    speak(vendor,
          "'Get your hyperreal hot‑dogs!  Two for one if you say the word \"bureau\"!'"),
    normal_text("He laughs maniacally and jots something down on a napkin."), !.

talk_to(_) :-
    writeln("There's no one to talk to.").

/* --- Combat --- */

combat(jesse, hiss_guard) :-
    location(jesse, upper_hall),
    has(jesse, service_weapon),          % require weapon before combat
    health(hiss_guard, HP),
    HP > 0,
    writeln("You fire the Service Weapon."),
    NewHP is HP - 12,
    retract(health(hiss_guard, HP)),
    assert(health(hiss_guard, NewHP)),
    format("Hiss Guard now has ~w HP.~n", [NewHP]),
    enemy_turn, !.

combat(jesse, hiss_guard) :-
    location(jesse, upper_hall),
    \+ has(jesse, service_weapon),
    writeln("You reach for a weapon... but you don't have the Service Weapon yet."), !.

combat(_, hiss_guard) :-
    writeln("There's nothing to attack here."), !.

/* --- Enemy Turn --- */

enemy_turn :-
    health(hiss_guard, HP),
    ( HP =< 0
    -> writeln("The Hiss Guard collapses into silence.")
    ;  writeln("The Hiss Guard lashes out!"),
       health(jesse, JHP),
       NewJHP is JHP - 8,
       retract(health(jesse, JHP)),
       assert(health(jesse, NewJHP)),
       format("You now have ~w HP.~n", [NewJHP])
    ).

/* --- Game Start --- */

start :-
    % show the map immediately, before any flavour text
    location(jesse, Room),
    show_map(Room),

    normal_text("You arrive at the Federal Bureau of Control."),
    normal_text("The building looms above you, humming with a strange, low resonance."),
    normal_text("Something pulls you toward the entrance."),
    writeln(""),
    tip_text("Tip: try 'enter' to go inside and continue the story. You can also go east to visit the food vendor; if stuck there, go west back to the street entrance."),
    writeln(""),
    tip_text("Tip: try 'help' to list all available commands."),
    writeln(""),
    % now print the description for the starting room
    description(Room, Desc),
    normal_text(Desc),          % description also coloured
    list_notes(Room),            % <--- mention notes at start
    list_occupants(Room),
    list_items(Room),

    game_loop.

/* --- Game Loop --- */

game_loop :-
    repeat,
    write("> "),
    read_line_to_string(user_input, Line),
    string_lower(Line, Lower),
    split_string(Lower, " ", " \t", Words0),
    maplist(clean_token, Words0, Words),          % remove punctuation
    maplist(atom_string, Tokens, Words),
    (   parse(Tokens, Command)
    ->  dispatch(Command),
        ( Command = quit -> ! ; fail )            % <--- fail unless quitting
    ;   writeln("I don't understand."),
        fail
    ).

/* --- Parser --- */

parse([go, Dir], go(Dir)).
parse([move, Dir], go(Dir)).
parse([walk, Dir], go(Dir)).

parse([look], look).
parse([look, at, Obj], look_at(Obj)).

parse([talk, ahti], talk(ahti)).
parse([talk, vendor], talk(vendor)).

parse([attack], attack).
parse([attack, hiss_guard], attack(hiss_guard)).

parse([take, Item], take(Item)).
parse([pick, up, Item], take(Item)).

parse([quit], quit).
parse([help], help).

parse([enter], go(enter)).
parse([go, inside], go(enter)).
parse([go, in], go(enter)).

parse([read], read(all)).
parse([read, note], read(all)).
parse([read, notes], read(all)).
parse([read, Name], read(Name)).
parse([read, note, Name], read(Name)).
parse([read, notes, Name], read(Name)).

parse([map], map).
parse([show, map], map).

/* --- Command Dispatch --- */

dispatch(look) :- !, describe_here.
dispatch(look_at(Obj)) :- !, look_at(Obj).
dispatch(go(Dir)) :- !, move(jesse, Dir).
dispatch(talk(ahti)) :- !, talk_to(ahti).
dispatch(talk(vendor)) :- !, talk_to(vendor).
dispatch(take(Obj)) :- !, take_item(Obj).
dispatch(attack) :- !, combat(jesse, hiss_guard).
dispatch(attack(hiss_guard)) :- !, combat(jesse, hiss_guard).
dispatch(read(Name)) :- !, read_notes(Name).
dispatch(map) :- !, location(jesse, Room), show_map(Room).
dispatch(quit) :- !, writeln("You step back from the House.").
dispatch(help) :- !, show_help.

dispatch(Cmd) :- format("I don't know how to handle: ~w~n", [Cmd]).

/* --- Tutorial Text --- */
show_help :-
    map_text("=== COMMANDS ==="),
    normal_text("Movement: go north | go south | go east | go west | enter"),
    normal_text("Look:     look | look at <thing>"),
    normal_text("Map:      map | show map"),
    normal_text("Read:     read | read <note_name>"),
    normal_text("Items:    take <item> | pick up <item>"),
    normal_text("Talk:     talk <npc>"),
    normal_text("Combat:   attack <enemy>"),
    normal_text("Help:     help"),
    normal_text("Quit:     quit"),
    map_text("----------------"),
    highlight_text("OBJECTIVE: Find your estranged brother in the mysterious Oldest House."),
    map_text("================").

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
    \+ connected(street, _, Dir),      % only block if no exit that way
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

map_label_center(Room, Label) :-
    format(atom(Label), "[>~w<]", [Room]).

label_with_status(Name, Status, Label) :-
    ( Status = locked
    -> format(atom(Label), "[~w] (locked)", [Name])
    ;  format(atom(Label), "[~w]", [Name])
    ).

dir_equiv(north, north).
dir_equiv(north, enter).
dir_equiv(south, south).
dir_equiv(south, exit).
dir_equiv(east, east).
dir_equiv(west, west).

neighbor(Current, Cardinal, DisplayNext, Status) :-
    dir_equiv(Cardinal, ConnDir),
    ( connected(Current, Next, ConnDir) ->
        ( Next \= Current
        -> DisplayNext = Next, Status = open
        ;  ( clause(connected(Current, Alt, ConnDir), _), Alt \= Current
           -> DisplayNext = Alt, Status = locked
           ;  fail
           )
        )
    ;  ( clause(connected(Current, Alt, ConnDir), _)
       -> DisplayNext = Alt, Status = locked
       ;  fail
       )
    ).

spaces(0, "").
spaces(N, S) :-
    N > 0,
    N1 is N - 1,
    spaces(N1, S1),
    atom_concat(" ", S1, S).

map_line(Fmt, Args) :-
    format(string(S), Fmt, Args),
    map_text(S).

center_start("", 0).
center_start(WLabel, Start) :-
    atom_length(WLabel, WL),
    Start is WL + 5.

show_map(Current) :-
    map_label_center(Current, Center),
    ( neighbor(Current, north, N, NStatus) -> label_with_status(N, NStatus, NLabel) ; NLabel = "" ),
    ( neighbor(Current, south, S, SStatus) -> label_with_status(S, SStatus, SLabel) ; SLabel = "" ),
    ( neighbor(Current, east, E, EStatus) -> label_with_status(E, EStatus, ELabel) ; ELabel = "" ),
    ( neighbor(Current, west, W, WStatus) -> label_with_status(W, WStatus, WLabel) ; WLabel = "" ),

    atom_length(Center, CL),
    center_start(WLabel, CenterStart),
    ArrowCol is CenterStart + CL // 2,
    spaces(ArrowCol, ArrowPad),

    map_text(""),
    map_text("Relative Map:"),

    ( NLabel \= "" ->
        atom_length(NLabel, NL),
        NCol is max(0, ArrowCol - NL // 2),
        spaces(NCol, NPad),
        map_line("~w~w", [NPad, NLabel]),
        map_line("~w^", [ArrowPad]),
        map_line("~w|", [ArrowPad])
    ; true ),

    ( (WLabel \= "", ELabel \= "") ->
        map_line("~w <-- ~w --> ~w", [WLabel, Center, ELabel])
    ; WLabel \= "" ->
        map_line("~w <-- ~w", [WLabel, Center])
    ; ELabel \= "" ->
        map_line("~w --> ~w", [Center, ELabel])
    ; map_line("~w", [Center])
    ),

    ( SLabel \= "" ->
        atom_length(SLabel, SL),
        SCol is max(0, ArrowCol - SL // 2),
        spaces(SCol, SPad),
        map_line("~w|", [ArrowPad]),
        map_line("~wv", [ArrowPad]),
        map_line("~w~w", [SPad, SLabel])
    ; true ),

    map_text("").

describe_here :-
    location(jesse, Room),
    show_map(Room),
    description(Room, Desc),
    normal_text(Desc),
    ( Room = food_vendor
    -> tip_text("Tip: if you're stuck, go west back to the street entrance to the Oldest House.")
    ; true
    ),
    list_notes(Room),
    list_occupants(Room),
    list_items(Room).

list_occupants(Room) :-
    findall(N, (location(N, Room), N \= jesse), Others),
    ( Others = [] -> true
    ; format(string(S),"You see: ~w",[Others]),
      highlight_text(S),
      ( member(vendor, Others)
      -> tip_text("Tip: perhaps you could 'talk vendor' while you're here.")
      ; true
      )
    ).

list_items(Room) :-
    findall(I, object(I, Room), Items),
    ( Items = [] -> true
    ; format(string(S),"Items here: ~w",[Items]),
      highlight_text(S)
    ).

% ensure game begins when invoked with `swipl game.pl`
:- initialization(start, main).

