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
:- dynamic max_health/2.
:- dynamic has/2.
:- dynamic read_note/2.
:- dynamic object/2.
:- dynamic weapon_charge/2.
:- dynamic max_weapon_charge/2.
:- dynamic last_color/1.        % must be dynamic for web mode retractall
:- discontiguous health/2.
:- use_module(library(pcre)).        % for re_replace/4
:- use_module(library(ansi_term)).   % for colour output

/* --- Helpers --- */

clean_token_smart(In, Out) :-
    % if input looks like it might be a code (has letters and numbers), keep it as-is
    (re_match('[a-z]+[0-9]|[0-9]+[a-z]'/i, In)
    -> Out = In
    ;  clean_token(In, Out)
    ).

clean_token(In, Out) :-
    re_replace('(^[^a-z]+|[^a-z]+$)'/i, '', In, Out).

% Output predicates — only defined when NOT loaded by server.pl
:- if(\+ current_module(server)).

last_color(default).

color_ln(Color, Text) :-
    last_color(LastColor),
    ( LastColor \= Color, LastColor \= default -> writeln("") ; true ),
    ansi_format([fg(Color)], '~w~n', [Text]),
    retract(last_color(LastColor)),
    assert(last_color(Color)).

space_if_color_changed :-
    last_color(LastColor),
    ( LastColor \= default -> writeln("") ; true ).

normal_text(Text) :-
    last_color(LastColor),
    ( LastColor \= green, LastColor \= default -> writeln("") ; true ),
    ansi_format([fg(green)], '~w~n', [Text]),
    retract(last_color(LastColor)),
    assert(last_color(green)).

highlight_text(Text) :-
    last_color(LastColor),
    ( LastColor \= yellow, LastColor \= default -> writeln("") ; true ),
    ansi_format([fg(yellow)], '~w~n', [Text]),
    retract(last_color(LastColor)),
    assert(last_color(yellow)).

map_text(Text) :-
    last_color(LastColor),
    ( LastColor \= cyan, LastColor \= default -> writeln("") ; true ),
    ansi_format([fg(cyan)], '~w~n', [Text]),
    retract(last_color(LastColor)),
    assert(last_color(cyan)).

tip_text(Text) :-
    last_color(LastColor),
    ( LastColor \= magenta, LastColor \= default -> writeln("") ; true ),
    ansi_format([fg(magenta), bold], '~w~n', [Text]),
    retract(last_color(LastColor)),
    assert(last_color(magenta)).

speak(ahti, Text)   :- ansi_format([fg(red), italic], '~w~n', [Text]).
speak(vendor, Text) :- ansi_format([fg(red), italic], '~w~n', [Text]).
speak(_, Text)      :- normal_text(Text).

note_text(Text) :-
    ansi_format([fg(red), italic], '~w~n', [Text]).

:- endif.

/* --- Initial State --- */

location(jesse, street).
location(ahti, janitor_hall).
% hiss_guard spawns when service_weapon is picked up
location(hiss_brute, atrium).
location(vendor, food_vendor).

health(jesse, 100).
max_health(jesse, 100).
health(hiss_guard, 30).
health(hiss_brute, 50).
weapon_charge(jesse, 10).
max_weapon_charge(jesse, 10).

/* --- Map --- */

connected(street, lobby, enter).
connected(street, lobby, north).
connected(lobby, street, exit).
connected(lobby, street, south).

connected(street, food_vendor, east).        % hot‑dog vendor
connected(food_vendor, street, west).

connected(street, west_road, west).         % was north
connected(west_road, street, east).         % was south

connected(lobby, janitor_hall, east).
connected(janitor_hall, lobby, west).

connected(janitor_hall, toilets, north).
connected(toilets, janitor_hall, south).

connected(janitor_hall, atrium, east) :-
    has(jesse, service_weapon).

connected(atrium, janitor_hall, west) :-
    has(jesse, service_weapon).

connected(lobby, upper_hall, north) :-
    has(jesse, keys).        % locked until you get keys

connected(lobby, lab77_locked, west) :-
    \+ has(jesse, lab77_key).

connected(lab77_locked, lobby, east) :-
    \+ has(jesse, lab77_key).

connected(lobby, lab77, west) :-
    has(jesse, lab77_key).

connected(lab77, lobby, east) :-
    has(jesse, lab77_key).

connected(lab77, secret_chamber, south) :-
    has(jesse, smash).

connected(secret_chamber, lab77, north) :-
    has(jesse, smash).

connected(upper_hall, directors_office, north).
connected(directors_office, upper_hall, south).
connected(upper_hall, lobby, south).        % return route from upper hall
connected(upper_hall, security_post, east).
connected(security_post, upper_hall, west).
connected(upper_hall, records_room, west).
connected(records_room, upper_hall, east).

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

description(toilets,
"A dimly lit bathroom. The smell of industrial cleaner hangs in the air. \
A first aid kit sits on the counter, weathered and faded.").

description(atrium,
"A vast circular chamber with high vaulted ceilings. Strange geometric patterns \
cover the floor, seeming to shift and breathe with an otherworldly rhythm. \
The air feels heavy with presence.").

description(upper_hall,
"A long corridor. A Hiss‑infected guard twitches violently.").

description(security_post,
"A small security post. Monitors flicker with static. An overturned chair \
suggests someone left in a hurry. A first aid kit sits on the desk.").

description(records_room,
"A dusty records room. Filing cabinets line the walls, many hanging open \
and emptied. The smell of old paper fills the air. A first aid kit \
sits on a shelf, untouched.").

description(directors_office,
"A quiet office bathed in pale light. The Director slumps behind the desk, \
a single bullet wound to the temple. In his outstretched hand — the Service Weapon. \
It hums faintly, as if waiting. Whatever drove him to this end, the weapon \
chose to stay. Pick it up. You'll need it.").

description(lab77_locked,
"A sealed laboratory door marked 'LAB 77' blocks your path. It's locked tight.").

description(lab77,
"Inside Lab 77. Equipment hums softly on the walls. A smash object sits on a bench.").

description(secret_chamber,
"A hidden chamber behind a crumbled wall. Strange equipment covers the shelves. Your brother sits slumped in a chair, eyes closed.").

/* --- Items --- */
object(keys, lobby).
object(service_weapon, directors_office).
object(locked_box, food_vendor).
object(smash, lab77).
object(health_upgrade, secret_chamber).
object(health_upgrade, toilets).
object(health_kit, lobby).
object(health_kit, security_post).
object(health_kit, records_room).
object(charge_upgrade, lobby).

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

note(food_vendor, menu,
    "A grease-stained menu board reads: 'TODAY'S SPECIAL: Bureau Burger - Code: BUREAU47'").

note(lab77, experiment_log,
    "Lab journal entry: 'The specimens respond to the resonance. Containment fields holding. —Dr. Darling'").

note(lab77, warning_sign,
    "A faded warning sign: 'DANGER: Dimensional Anomaly Active. Personnel must maintain safety protocols.'").

note(secret_chamber, research_log,
    "Faded research log: 'Subject exhibits anomalous properties. Further containment required. —Dr. Darling'").

note(secret_chamber, equipment_note,
    "Scrawled note: 'The Bureau's secrets buried deep. Some doors should stay locked.'").

note(secret_chamber, final_note,
    "A hastily written note: 'If you're reading this, then the House has let you in. Trust nothing. Find him and get out.'").

note(security_post, incident_report,
    "Incident report, partially burned: 'Officers responded to anomalous \
readings on floor 3. Two personnel unaccounted for. Recommend immediate \
evacuation of — ' The rest is ash.").

note(security_post, monitor_note,
    "Sticky note on a monitor: 'Camera 7 has been showing the same frame \
for three days. Maintenance says it's fine. Maintenance has not been seen since.'").

note(security_post, duty_roster,
    "A duty roster pinned to the wall. Every name has been crossed out \
in red ink. Yours is not on the list — but there's a blank line at the bottom.").

note(records_room, classified_memo,
    "Stamped CLASSIFIED: 'Project THRESHOLD — all documentation to be purged \
upon containment failure. If you are reading this, containment has failed.'").

note(records_room, personnel_file,
    "A personnel file, name redacted: 'Subject displays unusual resistance \
to paranatural influence. Recommended for Director programme. —Dr. Darling'").

note(records_room, filing_note,
    "Handwritten on a folder tab: 'DO NOT FILE UNDER H. The H files have \
been walking again.'").

note(records_room, torn_letter,
    "A torn letter, sender unknown: 'They said the House chooses its Director. \
I didn't believe them. I believe them now. Don't come looking for me.'").

note(directors_office, directors_journal,
    "The Director's open journal, final entry: 'The weapon spoke to me again last night. \
It said a name I didn't recognise. I wrote it down. I burned the page. \
I still hear it.'").

note(directors_office, memo_to_staff,
    "An unsent memo: 'To all Bureau staff — the situation is under control. \
Please disregard the sounds coming from the walls. This is normal. \
Everything is normal. —Director'").

% when you enter or start, tell player if there are unread notes
list_notes(Room) :-
    findall(Id, (note(Room,Id,_), \+ read_note(Room,Id)), Unread),
    ( Unread = [] -> true
    ; atomic_list_concat(Unread, ', ', IdStr),
      writeln(""),
      highlight_text("Unread notes here:"),
      note_text(IdStr),
      highlight_text("Use 'read <name>' to examine and read one."),
      writeln("")
    ).

% read all notes in current location, mark them as read
read_notes(all) :-
    location(jesse, Room),
    findall(Id-Text, (note(Room,Id,Text), \+ read_note(Room,Id)), Pairs),
    ( Pairs = []
    -> note_text("There's nothing to read here.")
    ; forall(member(Id-Text, Pairs),
             ( note_text(Text),
               assertz(read_note(Room,Id))
             ))
    ).

% read a single named note
read_notes(Name) :-
    location(jesse, Room),
    ( note(Room, Name, Text)
    -> ( read_note(Room, Name)
       -> note_text("You've already read that.")
       ;  note_text(Text),
          assertz(read_note(Room, Name))
       )
    ;  note_text("No such note here.")
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
    normal_text("There's no one to talk to.").

/* --- Combat --- */

combat(jesse, hiss_guard) :-
    location(jesse, upper_hall),
    \+ has(jesse, service_weapon),
    normal_text("You reach for a weapon... but you don't have the Service Weapon yet."), !.

combat(jesse, hiss_guard) :-
    location(jesse, upper_hall),
    has(jesse, service_weapon),
    health(hiss_guard, HP),
    HP > 0,
    !,
    weapon_charge(jesse, Charge),
    ( Charge =< 0
    -> highlight_text("Your weapon is out of charge! Use 'skip' to recharge.")
    ;  Dmg is 10,
       NewHP is HP - Dmg,
       retract(health(hiss_guard, HP)),
       assert(health(hiss_guard, NewHP)),
       NewCharge is Charge - 1,
       retract(weapon_charge(jesse, Charge)),
       assert(weapon_charge(jesse, NewCharge)),
       format(atom(Msg), "You fire! Hiss Guard health: ~w -> ~w", [HP, NewHP]),
       normal_text(Msg),
       enemy_turn
    ).

combat(jesse, hiss_guard) :-
    normal_text("The Hiss Guard is already dead."), !.

combat(_, hiss_guard) :-
    normal_text("There's nothing to attack here."), !.

enemy_turn :-
    health(hiss_guard, HP),
    ( HP =< 0
    -> highlight_text("═══════════════════════════════════"),
       highlight_text("The Hiss Guard collapses into silence."),
       highlight_text("═══════════════════════════════════")
    ;  normal_text("The Hiss Guard lashes out!"),
       health(jesse, JHP),
       NewJHP is JHP - 8,
       retract(health(jesse, JHP)),
       assert(health(jesse, NewJHP)),
       max_health(jesse, MaxHP),
       format(atom(HealthMsg), "Your Health: ~w/~w", [NewJHP, MaxHP]),
       highlight_text(HealthMsg),
       check_death
    ).

enemy_turn_brute :-
    health(hiss_brute, HP),
    ( HP =< 0
    -> highlight_text("═══════════════════════════════════"),
       highlight_text("The Hiss Brute collapses into silence."),
       highlight_text("═══════════════════════════════════")
    ;  normal_text("The Hiss Brute charges at you!"),
       health(jesse, JHP),
       NewJHP is JHP - 12,
       retract(health(jesse, JHP)),
       assert(health(jesse, NewJHP)),
       max_health(jesse, MaxHP),
       format(atom(HealthMsg), "Your Health: ~w/~w", [NewJHP, MaxHP]),
       highlight_text(HealthMsg),
       check_death
    ).

check_death :-
    health(jesse, HP),
    ( HP =< 0
    -> highlight_text(""),
       highlight_text("╔═══════════════════════════════════╗"),
       highlight_text("║           GAME  OVER              ║"),
       highlight_text("╚═══════════════════════════════════╝"),
       normal_text("You have succumbed to the Hiss. The House claims another soul."),
       normal_text("Type 'restart' to try again."),
       game_loop   % keep loop running so player can restart
    ; true
    ).

skip_turn :-
    location(jesse, Room),
    living_enemy_here(Room),
    !,
    ( location(hiss_brute, Room), health(hiss_brute, HP), HP > 0
    -> normal_text("You hold your ground. The enemy seizes the moment..."),
       enemy_turn_brute
    ;  normal_text("You hold your ground. The enemy seizes the moment..."),
       enemy_turn
    ).

skip_turn :-
    normal_text("You can only skip your turn during combat.").

/* --- Enemy Helpers --- */

living_enemy_here(Room) :-
    location(hiss_guard, Room),
    health(hiss_guard, HP),
    HP > 0,
    has(jesse, service_weapon).  % only "real" if player can see/fight it

living_enemy_here(Room) :-
    location(hiss_brute, Room),
    health(hiss_brute, HP),
    HP > 0,
    has(jesse, service_weapon).

/* --- Game Start --- */

start :-
    % show the map immediately, before any flavour text
    location(jesse, Room),
    show_map(Room),

    normal_text("You arrive at the Federal Bureau of Control."),
    normal_text("The building looms above you, humming with a strange, low resonance."),
    normal_text("Something pulls you toward the entrance."),
    space_if_color_changed,
    tip_text("Tip: try 'enter' or 'go north' to go inside and continue the story. You can also go east to visit the food vendor; if stuck there, go west back to the street entrance."),
    space_if_color_changed,
    tip_text("Tip: try 'help' to list all available commands."),
    space_if_color_changed,
    description(Room, Desc),
    normal_text(Desc),
    list_notes(Room),
    list_occupants(Room),
    list_items(Room),
    game_loop.

/* --- Game Loop --- */

game_loop :-
    write("> "),
    read_line_to_string(user_input, Line),
    string_lower(Line, Lower),
    split_string(Lower, " ", " \t", Words0),
    maplist(clean_token_smart, Words0, Words),
    maplist(atom_string, Tokens, Words),
    (   parse(Tokens, Command)
    ->  dispatch(Command),
        ( Command = quit
        -> true
        ;  game_loop
        )
    ;   writeln("I don't understand."),
        game_loop
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
parse([attack, hiss_brute], attack(hiss_brute)).

parse([take, Item], take(Item)).
parse([pick, up, Item], take(Item)).

parse([quit], quit).
parse([help], help).
parse([health], health).
parse([status], health).
parse([charge], charge).
parse([skip], skip).
parse([wait], skip).

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

parse([unlock, Item], unlock(Item, none)).
parse([unlock, Item, Code], unlock(Item, Code)).

parse([restart], restart).
parse([new, game], restart).
parse([start, over], restart).

/* --- Command Dispatch --- */

dispatch(look) :- !, describe_here.
dispatch(look_at(Obj)) :- !, look_at(Obj).
dispatch(go(Dir)) :- !, move(jesse, Dir, Moved), ( Moved = moved -> describe_here ; true ).
dispatch(talk(ahti)) :- !, talk_to(ahti).
dispatch(talk(vendor)) :- !, talk_to(vendor).
dispatch(take(Obj)) :- !, take_item(Obj).
dispatch(attack) :-
    !,
    location(jesse, Room),
    ( living_enemy_here(Room)
    -> ( location(hiss_brute, Room), health(hiss_brute, HP), HP > 0
       -> combat(jesse, hiss_brute)
       ;  combat(jesse, hiss_guard)
       )
    ;  normal_text("There's nothing to attack here.")
    ).
dispatch(attack(hiss_guard)) :- !, combat(jesse, hiss_guard).
dispatch(attack(hiss_brute)) :- !, combat(jesse, hiss_brute).
dispatch(skip) :- !, skip_turn.
dispatch(unlock(Item, Code)) :- !, unlock_item(Item, Code).
dispatch(restart) :- !, restart_game.
dispatch(read(Name)) :- !, read_notes(Name).
dispatch(health) :- !, show_health.
dispatch(charge) :- !, show_charge.
dispatch(map) :- !, location(jesse, Room), show_map(Room).
dispatch(quit) :- !, normal_text("You step back from the House.").
dispatch(help) :- !, show_help.

dispatch(Cmd) :- format("I don't know how to handle: ~w~n", [Cmd]).

/* --- Tutorial Text --- */
show_help :-
    map_text("=== COMMANDS ==="),
    normal_text("Movement:  go north | go south | go east | go west | enter"),
    normal_text("Look:      look | look at <thing>"),
    normal_text("Map:       map | show map"),
    normal_text("Read:      read | read <note_name>"),
    normal_text("Items:     take <item> | pick up <item>"),
    normal_text("Inventory: inventory | inv | i"),
    normal_text("Talk:      talk <npc>"),
    normal_text("Unlock:    unlock <item> <code>"),
    normal_text("Combat:    attack <enemy>"),
    normal_text("Skip:      skip | wait (let enemy attack, recharge weapon)"),
    normal_text("Health:    health | status"),
    normal_text("Charge:    charge (show weapon charge)"),
    normal_text("Restart:   restart | new game | start over"),
    normal_text("Help:      help"),
    normal_text("Quit:      quit"),
    map_text("----------------"),
    highlight_text("OBJECTIVE: Find your estranged brother in the mysterious Oldest House."),
    map_text("================").

show_health :-
    health(jesse, HP),
    max_health(jesse, MaxHP),
    format(atom(Msg), "Health: ~w/~w", [HP, MaxHP]),
    highlight_text(Msg).

show_charge :-
    ( has(jesse, service_weapon)
    -> weapon_charge(jesse, Charge),
       max_weapon_charge(jesse, MaxCharge),
       format(atom(Msg), "Service Weapon Charge: ~w/~w", [Charge, MaxCharge]),
       highlight_text(Msg)
    ; highlight_text("You need to pick up the Service Weapon first.")
    ).

/* Funny Text */
funny_outside_message :-
    outside_attempts(N),
    N1 is N + 1,
    retract(outside_attempts(N)),
    assert(outside_attempts(N1)),
    outside_message(N1).

outside_message(1) :-
    normal_text("You take a few steps away… then stop. Something feels wrong."),
    normal_text("The building hums louder, like it's watching you.").

outside_message(2) :-
    normal_text("You try to walk off, but your feet feel heavy."),
    normal_text("Almost like the building is disappointed in you.").

outside_message(3) :-
    normal_text("You turn around again. The Bureau is still there."),
    normal_text("It feels… expectant. Maybe go inside?").

outside_message(4) :-
    normal_text("You walk in a circle. The street loops."),
    normal_text("Okay, the House is definitely messing with you now.").

outside_message(_) :-
    normal_text("You cannot escape the Oldest House. Just go inside.").

:- dynamic outside_attempts/1.
outside_attempts(0).

/* --- Movement --- */
move(jesse, Dir, blocked) :-
    location(jesse, street),
    Dir \= enter,
    \+ connected(street, _, Dir),
    funny_outside_message,
    !.

move(jesse, _, blocked) :-
    location(jesse, Room),
    living_enemy_here(Room),
    !,
    highlight_text("You can't leave — there's still an enemy here!").

move(jesse, north, blocked) :-
    location(jesse, lobby),
    \+ has(jesse, keys),
    !,
    highlight_text("The door to the upper hall is locked. You need keys to open it.").

move(jesse, west, blocked) :-
    location(jesse, lobby),
    \+ has(jesse, lab77_key),
    !,
    highlight_text("The door to Lab 77 is sealed and locked. You need a key to open it.").

move(jesse, east, blocked) :-
    location(jesse, janitor_hall),
    \+ has(jesse, service_weapon),
    !,
    speak(ahti, "'The Service Weapon... you will need it. The deeper places demand it. Without it, the shadows will consume you. Go. Retrieve what was left behind.'").

move(Actor, Dir, moved) :-
    location(Actor, Room),
    connected(Room, Next, Dir),
    !,
    retract(location(Actor, Room)),
    assert(location(Actor, Next)).

move(_, _, blocked) :-
    normal_text("You can't go that way.").

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
    !,
    show_map(Room),
    description(Room, Desc),
    normal_text(Desc),
    ( Room = food_vendor
    -> tip_text("Tip: if you're stuck, go west back to the street entrance to the Oldest House."),
       tip_text("Tip: try 'unlock locked_box <code>' if you find a clue."),
       space_if_color_changed
    ; true
    ),
    list_notes(Room),
    list_occupants(Room),
    list_items(Room).

list_occupants(Room) :-
    findall(N, (location(N, Room), N \= jesse), Others),
    ( Others = [] -> true
    ;   include(visible_npc, Others, FilteredOthers),
        ( FilteredOthers = [] -> true
        ; format(string(S),"You see: ~w",[FilteredOthers]),
          highlight_text(S),
          ( member(ahti, FilteredOthers), has(jesse, service_weapon)
          -> tip_text("Tip: perhaps you could 'talk ahti' while you're here."),
             space_if_color_changed
          ; member(vendor, FilteredOthers)
          -> tip_text("Tip: perhaps you could 'talk vendor' while you're here."),
             space_if_color_changed
          ; member(hiss_guard, FilteredOthers)
          -> tip_text("Tip: use 'attack' to deal damage to the Hiss Guard!"),
             space_if_color_changed
          ; member(hiss_brute, FilteredOthers)
          -> tip_text("Tip: use 'attack' to deal damage to the Hiss Brute!"),
             space_if_color_changed
          ; true
          )
        )
    ).

visible_npc(hiss_guard) :- has(jesse, service_weapon), !.
visible_npc(hiss_guard) :- !, fail.
visible_npc(hiss_brute) :- has(jesse, service_weapon), !.
visible_npc(hiss_brute) :- !, fail.
visible_npc(_).

list_items(Room) :-
    findall(I, object(I, Room), Items),
    ( Items = [] -> true
    ; atomic_list_concat(Items, ', ', ItemStr),
      writeln(""),
      highlight_text("Items here:"),
      note_text(ItemStr),
      highlight_text("Use 'take <item>' to pick something up."),
      writeln("")
    ).

take_item(Item) :-
    location(jesse, Room),
    atom_string(Item, ItemStr),
    string_lower(ItemStr, ItemLower),
    atom_string(ItemAtom, ItemLower),
    findall(Obj, object(Obj, Room), Objects),
    member(MatchObj, Objects),
    atom_string(MatchObj, ObjStr),
    string_lower(ObjStr, ObjLower),
    atom_string(ObjAtom, ObjLower),
    ( ObjAtom = ItemAtom ; atom_concat(ItemAtom, 's', ObjAtom) ; atom_concat(ObjAtom, 's', ItemAtom) ),
    !,
    ( MatchObj = health_upgrade
    -> max_health(jesse, MaxHP),
       retract(object(MatchObj, Room)),
       NewMaxHP is MaxHP + 5,
       retract(max_health(jesse, MaxHP)),
       assert(max_health(jesse, NewMaxHP)),
       health(jesse, HP),
       NewHP is min(NewMaxHP, HP + 5),
       retract(health(jesse, HP)),
       assert(health(jesse, NewHP)),
       assertz(has(jesse, MatchObj)),
       format(atom(M), "Max health increased from ~w to ~w/~w", [MaxHP, NewHP, NewMaxHP]),
       normal_text(M)
    ; MatchObj = charge_upgrade
    -> max_weapon_charge(jesse, MaxCharge),
       retract(object(MatchObj, Room)),
       NewMaxCharge is MaxCharge + 2,
       retract(max_weapon_charge(jesse, MaxCharge)),
       assert(max_weapon_charge(jesse, NewMaxCharge)),
       weapon_charge(jesse, Charge),
       NewCharge is min(NewMaxCharge, Charge + 2),
       retract(weapon_charge(jesse, Charge)),
       assert(weapon_charge(jesse, NewCharge)),
       assertz(has(jesse, MatchObj)),
       format(atom(M), "Max weapon charge increased from ~w to ~w/~w", [MaxCharge, NewCharge, NewMaxCharge]),
       normal_text(M)
    ; MatchObj = health_kit
    -> health(jesse, HP),
       max_health(jesse, MaxHP),
       retract(object(MatchObj, Room)),
       ( HP >= MaxHP
       -> highlight_text("You are already at full health.")
       ; retract(health(jesse, HP)),
         assert(health(jesse, MaxHP)),
         assertz(has(jesse, MatchObj)),
         format(atom(M), "Health restored to ~w/~w", [MaxHP, MaxHP]),
         normal_text(M)
       )
    ; retract(object(MatchObj, Room)),
      assertz(has(jesse, MatchObj)),
      format(atom(M), "You take the ~w.", [MatchObj]),
      normal_text(M),
      ( MatchObj = service_weapon
      -> assertz(location(hiss_guard, upper_hall)),
         highlight_text("A distant screech echoes through the building...")
      ; true
      )
    ).

take_item(Item) :-
    format(atom(Msg), "There's no ~w here to take.", [Item]),
    normal_text(Msg).

look_at(Obj) :-
    format(atom(Msg), "You examine the ~w closely, but see nothing special.", [Obj]),
    normal_text(Msg).

unlock_item(Item, Code) :-
    atom_string(Item, ItemStr),
    string_lower(ItemStr, ItemLower),
    atom_string(ItemAtom, ItemLower),
    ( ItemAtom = locked_box
    -> ( Code = none
       -> location(jesse, food_vendor),
          object(locked_box, food_vendor),
          !,
          tip_text("Usage: unlock locked_box <code>")
       ; location(jesse, food_vendor),
         object(locked_box, food_vendor),
         !,
         ( Code == bureau47
         -> retract(object(locked_box, food_vendor)),
            assertz(has(jesse, lab77_key)),
            highlight_text("You unlock the box and find a Lab 77 key inside!"),
            tip_text("The lab77_key has been added to your inventory.")
         ;  color_ln(red, "That's not the right code.")
         )
       )
    ; format(string(S), "You can't unlock the ~w.~n", [Item]),
      color_ln(red, S)
    ).

restart_game :-
    % retract all dynamic state
    retractall(location(_, _)),
    retractall(health(_, _)),
    retractall(max_health(_, _)),
    retractall(weapon_charge(_, _)),
    retractall(max_weapon_charge(_, _)),
    retractall(has(_, _)),
    retractall(read_note(_, _)),
    retractall(outside_attempts(_)),
    retractall(object(_, _)),
    
    % restore initial state
    assertz(location(jesse, street)),
    assertz(location(ahti, janitor_hall)),
    % hiss_guard spawns when service_weapon is picked up
    assertz(location(hiss_brute, atrium)),
    assertz(location(vendor, food_vendor)),
    assertz(health(jesse, 100)),
    assertz(max_health(jesse, 100)),
    assertz(weapon_charge(jesse, 10)),
    assertz(max_weapon_charge(jesse, 10)),
    assertz(health(hiss_guard, 30)),
    assertz(health(hiss_brute, 50)),
    assertz(outside_attempts(0)),
    assertz(object(keys, lobby)),
    assertz(object(service_weapon, directors_office)),
    assertz(object(locked_box, food_vendor)),
    assertz(object(smash, lab77)),
    assertz(object(health_upgrade, secret_chamber)),
    assertz(object(health_upgrade, toilets)),
    assertz(object(charge_upgrade, lobby)),
    assertz(object(health_kit, lobby)),
    assertz(object(health_kit, security_post)),
    assertz(object(health_kit, records_room)),
    
    % restart game
    normal_text("Game restarted!"),
    init_game_output.   % web-safe: no game_loop call

% Change the final line — only auto-start when loaded directly, not as a library
% Replace the existing :- initialization line at the bottom with:
:- if(\+ current_module(server)).
:- initialization(start, main).
:- endif.

