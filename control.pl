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
:- dynamic last_color/1.
:- dynamic game_over/0.
:- dynamic health_kit_tip_shown/0.
:- dynamic attack_tip_shown/0.
:- dynamic hiss_infected/1.
:- dynamic weapon_just_taken/0.
:- dynamic cat_statue_placed/0.
:- dynamic shield_active/0.
:- discontiguous health/2.
:- discontiguous combat/2.
:- discontiguous visible_npc/1.
:- discontiguous inner_thought/3.
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

thought_text(Text) :-
    ansi_format([fg(white), italic], '~w~n', [Text]).

:- endif.

/* --- NPC Visibility --- */

visible_npc(ahti).
visible_npc(vendor).
visible_npc(dylan).
visible_npc(E) :-
    is_hiss_enemy(E),
    has(jesse, service_weapon).

/* --- Enemy Announcement on Room Entry --- */

announce_enemies(Room) :-
    findall(EName, (
        location(E, Room),
        is_hiss_enemy(E),
        has(jesse, service_weapon),
        health(E, HP), HP > 0,
        enemy_display_name(E, EName)
    ), Names),
    ( Names \= []
    -> forall(member(N, Names), (
           format(string(S), "Enemy spotted: ~w", [N]),
           highlight_text(S)
       )),
       ( attack_tip_shown -> true
       ; tip_text("Use 'attack' to fight!"),
         assertz(attack_tip_shown)
       )
    ; true
    ).

/* --- Initial State --- */

location(jesse, street).
location(ahti, janitor_hall).
location(hiss_brute, atrium).
location(hiss_guard_b, containment_hall).
location(hiss_boss, solitary).
location(vendor, food_vendor).
location(dylan, dylans_cell).

health(jesse, 100).
max_health(jesse, 100).
% health(hiss_guard, 30) is asserted when service_weapon is picked up
health(hiss_brute, 50).
health(hiss_guard_b, 30).
health(hiss_boss, 100).
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

connected(atrium, containment_hall, east) :-
    has(jesse, service_weapon).

connected(containment_hall, atrium, west) :-
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

% Add connection after directors_office/upper_hall connections:
connected(directors_office, demolition_room, north).
connected(demolition_room, directors_office, south).
connected(demolition_room, death_room, north).
connected(death_room, demolition_room, south).

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

description(containment_hall,
"A long reinforced corridor. Containment cells line both walls, most of them \
hanging open and dark. The air smells of ozone and fear. A Hiss-infected guard \
patrols the far end, twitching erratically.").

description(solitary,
"A cavernous solitary confinement block. The cells here are reinforced with \
paranatural dampeners — thick runes etched into every surface. Most of the doors \
have been torn clean off their hinges from the inside. \
At the far end of the block, something massive stands perfectly still, \
facing the wall. It turns slowly as you enter. \
The Hiss Warden. It was left here to guard something. \
Or someone.").

description(upper_hall,
"A long corridor leading deeper into the Bureau. The air hums with a faint \
paranatural resonance. Doors line the walls, some hanging open, others sealed tight.").

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

description(demolition_room,
"A ruined chamber, walls blasted inward as if by some enormous force. \
Debris litters the floor. In the centre, hovering inches above a scorched pedestal, \
a translucent hexagonal shield pulses with a pale blue light. \
An Object of Power. It knows you're here.").

description(death_room,
"The air tears open. A wall of pure resonant noise hits you like a physical blow. \
The Hiss is not here — the Hiss IS here, everywhere, in every atom of the room. \
You had one second to reconsider. You didn't take it.").

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
object(health_kit, containment_hall).
object(charge_upgrade, atrium).
object(cat_statue, upper_hall).
object(flower, street).
object(shield, demolition_room).
object(health_kit, solitary).

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

note(demolition_room, important,
    "*** IMPORTANT *** Scrawled in large, frantic letters across a torn Bureau memo: \
'DO NOT ENTER THE ROOM TO THE NORTH. I REPEAT — DO NOT ENTER. \
Three agents went in. None came back. Whatever is in there is not containable. \
It is not survivable. Turn around. GO SOUTH. —Last surviving member of Retrieval Team 7'").

note(atrium, cat_plinth,
    "A circular stone plinth sits at the centre of the atrium floor. \
An inscription reads: 'The Watcher returns the way.' \
A shallow recess on top looks like something should rest there.").

note(atrium, geometric_inscription,
    "Etched into the floor around the plinth, in a language that shouldn't be readable \
but somehow is: 'The Astral Cat stood here before time was counted. \
Return it and the House remembers.'").

note(atrium, research_scrawl,
    "A torn page from a researcher's notebook, wedged under the plinth: \
'The resonance patterns converge at this point. Whatever belonged here \
has been moved to the upper level for safekeeping. Bad idea. \
The room has been wrong ever since. —R.H.'").

note(upper_hall, evacuation_notice,
    "A laminated evacuation notice, corners curling: 'In the event of a paranatural \
incursion, proceed calmly to the nearest exit. Do not run. Do not look back. \
Do not describe what you have seen to non-Bureau personnel.'").

note(upper_hall, scratched_wall,
    "Words scratched into the wall at eye level, jagged and desperate: \
'IT FOLLOWS THE SOUND. STAY QUIET.'").

note(upper_hall, torn_memo,
    "A torn internal memo: '...all personnel above clearance level 4 are advised \
to avoid the upper corridor after 22:00. Unauthorised resonance has been detected \
near the Director's office. This is not a drill. —Security Division'").

note(upper_hall, sticky_note,
    "A sticky note on a door handle: 'Keys still missing. Do NOT prop this door open. \
Last time cost us three agents and a filing cabinet. —M'").

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

/* --- Inner Thoughts --- */
% inner_thought(Room, Id, Text).

inner_thought(street, brother,
    "Dylan. You haven't seen him in years — not since the night everything \
fell apart. He disappeared without a word, and you told yourself you didn't care. \
You told yourself that for a long time. \
Then the dreams started. His voice. This building. \
Something in here took him, or called him, or changed him. \
You don't know which is worse. \
You just know you're not leaving without him.").

inner_thought(street, here,
    "The Federal Bureau of Control. You used to think it was a myth — \
a government agency that didn't officially exist, dealing with things \
that officially couldn't happen. \
Now you're standing in front of it. \
It's taller than it should be. The geometry is wrong in ways you can't name. \
And somehow, it feels like it already knows you're here.").

inner_thought(lobby, weapon,
    "You need the Service Weapon. You've heard about it — \
an Object of Power, a gun that chooses its Director. \
The last Director is dead. \
Which means it's waiting for someone new. \
Maybe that's you. \
You're not sure if that's terrifying or exactly what you came here for.").

inner_thought(lobby, brother,
    "He came here. You're sure of it now. The feeling gets stronger the deeper \
you go — like the building is confirming it, room by room. \
He always did get drawn to the wrong things.").

inner_thought(lobby, layout,
    "This place makes no sense. \
From the outside it looked like a normal government building — maybe ten, twelve floors. \
But in here the geometry is wrong. Corridors that shouldn't fit. Rooms that open onto other rooms \
with no space between them. \
You've been in two hallways and already you've lost your sense of direction. \
The Bureau calls it the Oldest House. \
You're starting to understand why. \
It doesn't feel built. It feels grown.").

inner_thought(lobby, exploration,
    "Dylan could be anywhere in here. \
That's the reality you have to sit with. \
This building doesn't follow normal rules — rooms shift, corridors loop, \
whole wings show up where they shouldn't be. \
You're going to have to search every corridor. Every office. Every locked door you can find a key for. \
Leave no room unchecked. \
He's here. And you're not leaving until you find him.").

inner_thought(atrium, patterns,
    "The floor is doing something. Moving, almost — or just on the edge of moving. \
You've seen geometry like this before. In the dreams. \
There's something missing here. Something that should be here and isn't. \
The room feels incomplete. Wrong. \
Like a sentence with the last word cut out.").

inner_thought(secret_chamber, dylan,
    "There he is. Dylan. \
He looks smaller than you remember. Older. \
Whatever happened to him in here, he's still breathing. \
That's enough. That has to be enough. \
You just have to get him out.").

list_thoughts(Room) :-
    findall(Id, inner_thought(Room, Id, _), Thoughts),
    ( Thoughts = [] -> true
    ; atomic_list_concat(Thoughts, ', ', IdStr),
      writeln(""),
      highlight_text("Jesse's thoughts:"),
      note_text(IdStr),
      highlight_text("Use 'think <thought>' to reflect."),
      writeln("")
    ).

think_thought(Name) :-
    location(jesse, Room),
    ( inner_thought(Room, Name, Text)
    -> normal_text(Text)
    ;  normal_text("You can't focus on that right now.")
    ).

/* --- Place Item --- */

place_item(cat_statue) :-
    location(jesse, atrium),
    has(jesse, cat_statue),
    \+ cat_statue_placed,
    !,
    retract(has(jesse, cat_statue)),
    assertz(cat_statue_placed),
    highlight_text("You set the cat statue on the stone plinth."),
    normal_text("It fits perfectly. The geometric patterns on the floor pulse once, faintly, then settle."),
    normal_text("A deep resonant tone fills the chamber. Two objects materialise from the light."),
    assertz(object(health_upgrade, atrium)),
    assertz(object(charge_upgrade, atrium)),
    tip_text("New items have appeared! Use 'take health_upgrade' and 'take charge_upgrade'.").

place_item(cat_statue) :-
    cat_statue_placed,
    !,
    normal_text("The cat statue is already placed on the plinth.").

place_item(cat_statue) :-
    \+ location(jesse, atrium),
    has(jesse, cat_statue),
    !,
    normal_text("That doesn't seem like the right place for it. The statue feels drawn elsewhere.").

place_item(cat_statue) :-
    normal_text("You don't have the cat statue.").

place_item(flower) :-
    location(jesse, west_road),
    has(jesse, flower),
    !,
    retract(has(jesse, flower)),
    assertz(object(health_kit, west_road)),
    highlight_text("You lay the wildflower against the old brick wall."),
    normal_text("It looks right here. Like it belonged all along."),
    normal_text("Something shifts in the air — a faint warmth, almost grateful."),
    tip_text("A health kit has appeared! Use 'take health_kit' to pick it up.").

place_item(flower) :-
    \+ location(jesse, west_road),
    has(jesse, flower),
    !,
    normal_text("You hold the flower carefully. It feels like it belongs somewhere quieter than this.").

place_item(flower) :-
    normal_text("You don't have a flower.").

place_item(Item) :-
    format(atom(Msg), "You can't place the ~w here.", [Item]),
    normal_text(Msg).

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

talk_to(dylan) :-
    location(jesse, dylans_cell),
    !,
    speak(dylan, "'Jesse.'"),
    normal_text("He stands slowly. He looks like he hasn't slept in weeks. Maybe months."),
    speak(dylan, "'I knew you'd come. I told them you would. They didn't believe me.'"),
    normal_text("You don't say anything. There's nothing to say yet."),
    speak(dylan, "'How bad is it out there?'"),
    normal_text("You look at the Service Weapon in your hand. You think about every room you walked through to get here."),
    speak(dylan, "'That bad. Okay.'"),
    normal_text("He crosses the cell and stands beside you."),
    speak(dylan, "'Let's go home, Jesse.'"),
    normal_text(""),
    normal_text("You walk out together. The House lets you."),
    normal_text("For now, that's enough."),
    normal_text(""),
    show_credits.

talk_to(_) :-
    normal_text("There's no one to talk to.").

show_credits :-
    map_text(""),
    map_text("╔══════════════════════════════════════════╗"),
    map_text("║               ~ FIN ~                    ║"),
    map_text("╠══════════════════════════════════════════╣"),
    map_text("║                                          ║"),
    map_text("║   CONTROL - TEXT ADVENTURE               ║"),
    map_text("║                                          ║"),
    map_text("║   Written in Prolog                      ║"),
    map_text("║                                          ║"),
    map_text("║   Inspired by Remedy Entertainment's     ║"),
    map_text("║   CONTROL (2019)                         ║"),
    map_text("║                                          ║"),
    map_text("║   Jesse found Dylan.                     ║"),
    map_text("║   The House remains.                     ║"),
    map_text("║   It always does.                        ║"),
    map_text("║                                          ║"),
    map_text("╚══════════════════════════════════════════╝"),
    map_text(""),
    highlight_text("Type 'restart' to play again or 'quit' to exit."),
    assertz(game_over).

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

combat(jesse, hiss_guard_b) :-
    location(jesse, Room),
    location(hiss_guard_b, Room),
    has(jesse, service_weapon),
    health(hiss_guard_b, HP),
    HP > 0,
    !,
    weapon_charge(jesse, Charge),
    ( Charge =< 0
    -> highlight_text("Your weapon is out of charge! Use 'skip' to recharge.")
    ;  Dmg is 10,
       NewHP is HP - Dmg,
       retract(health(hiss_guard_b, HP)),
       assert(health(hiss_guard_b, NewHP)),
       NewCharge is Charge - 1,
       retract(weapon_charge(jesse, Charge)),
       assert(weapon_charge(jesse, NewCharge)),
       format(atom(Msg), "You fire! Hiss Guard health: ~w -> ~w", [HP, NewHP]),
       normal_text(Msg),
       enemy_turn_guard_b
    ).

combat(jesse, hiss_guard_b) :-
    normal_text("The Hiss Guard is already dead."), !.

combat(_, hiss_guard) :-
    normal_text("There's nothing to attack here."), !.

enemy_turn :-
    health(hiss_guard, HP),
    ( HP =< 0
    -> highlight_text("═══════════════════════════════════"),
       highlight_text("The Hiss Guard collapses into silence."),
       highlight_text("═══════════════════════════════════"),
       ( location(hiss_guard, DeadRoom) -> retract(location(hiss_guard, DeadRoom)) ; true ),
       max_weapon_charge(jesse, MaxCharge),
       retract(weapon_charge(jesse, _)),
       assertz(weapon_charge(jesse, MaxCharge)),
       format(atom(RechargeMsg), "Service Weapon recharged to ~w/~w.", [MaxCharge, MaxCharge]),
       highlight_text(RechargeMsg),
       ( health_kit_tip_shown -> true
       ; tip_text("Tip: took some damage? Look for health_kit items in rooms to restore your health."),
         assertz(health_kit_tip_shown)
       )
    ;  normal_text("The Hiss Guard lashes out!"),
       ( shield_active
       -> retract(shield_active),
          highlight_text("The shield absorbs the blow! You take no damage."),
          highlight_text("The shield's barrier dissipates.")
       ;  health(jesse, JHP),
          NewJHP is JHP - 25,
          retract(health(jesse, JHP)),
          assert(health(jesse, NewJHP)),
          max_health(jesse, MaxHP),
          format(atom(HealthMsg), "Your Health: ~w/~w", [NewJHP, MaxHP]),
          highlight_text(HealthMsg),
          weapon_charge(jesse, Charge),
          max_weapon_charge(jesse, MaxCharge),
          format(atom(ChargeMsg), "Weapon Charge: ~w/~w", [Charge, MaxCharge]),
          highlight_text(ChargeMsg),
          check_death
       )
    ).

enemy_turn_guard_b :-
    health(hiss_guard_b, HP),
    ( HP =< 0
    -> highlight_text("═══════════════════════════════════"),
       highlight_text("The Hiss Guard collapses into silence."),
       highlight_text("═══════════════════════════════════"),
       ( location(hiss_guard_b, DeadRoom) -> retract(location(hiss_guard_b, DeadRoom)) ; true ),
       max_weapon_charge(jesse, MaxCharge),
       retract(weapon_charge(jesse, _)),
       assertz(weapon_charge(jesse, MaxCharge)),
       format(atom(RechargeMsg), "Service Weapon recharged to ~w/~w.", [MaxCharge, MaxCharge]),
       highlight_text(RechargeMsg)
    ;  normal_text("The Hiss Guard lashes out!"),
       ( shield_active
       -> retract(shield_active),
          highlight_text("The shield absorbs the blow! You take no damage."),
          highlight_text("The shield's barrier dissipates.")
       ;  health(jesse, JHP),
          NewJHP is JHP - 25,
          retract(health(jesse, JHP)),
          assert(health(jesse, NewJHP)),
          max_health(jesse, MaxHP),
          format(atom(HealthMsg), "Your Health: ~w/~w", [NewJHP, MaxHP]),
          highlight_text(HealthMsg),
          weapon_charge(jesse, Charge),
          max_weapon_charge(jesse, MaxCharge),
          format(atom(ChargeMsg), "Weapon Charge: ~w/~w", [Charge, MaxCharge]),
          highlight_text(ChargeMsg),
          check_death
       )
    ).

check_death :-
    health(jesse, HP),
    ( HP =< 0
    -> assertz(game_over),
       highlight_text(""),
       highlight_text("╔═══════════════════════════════════╗"),
       highlight_text("║           GAME  OVER              ║"),
       highlight_text("╚═══════════════════════════════════╝"),
       normal_text("You have succumbed to the Hiss. The House claims another soul."),
       normal_text("Type 'restart' to try again.")
    ; true
    ).

skip_turn :-
    location(jesse, Room),
    living_enemy_here(Room),
    !,
    weapon_charge(jesse, OldCharge),
    max_weapon_charge(jesse, MaxCharge),
    ( OldCharge >= MaxCharge
    -> highlight_text("Your Service Weapon charge is already at maximum!")
    ;  NewCharge is min(MaxCharge, OldCharge + 1),
       retract(weapon_charge(jesse, OldCharge)),
       assertz(weapon_charge(jesse, NewCharge)),
       format(atom(ChargeMsg), "Weapon recharged: ~w -> ~w/~w", [OldCharge, NewCharge, MaxCharge]),
       highlight_text(ChargeMsg)
    ),
    ( location(hiss_brute, Room), health(hiss_brute, HP), HP > 0
    -> normal_text("You hold your ground. The enemy seizes the moment..."),
       enemy_turn_brute
    ;  location(hiss_guard_b, Room), health(hiss_guard_b, HP2), HP2 > 0
    -> normal_text("You hold your ground. The enemy seizes the moment..."),
       enemy_turn_guard_b
    ;  location(Enemy, Room), atom_concat(hiss_infection_, _, Enemy),
       health(Enemy, EHP), EHP > 0
    -> normal_text("You hold your ground. The enemy seizes the moment..."),
       enemy_turn_infection(Enemy, Room)
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
    location(hiss_guard_b, Room),
    health(hiss_guard_b, HP),
    HP > 0,
    has(jesse, service_weapon).

living_enemy_here(Room) :-
    location(hiss_brute, Room),
    health(hiss_brute, HP),
    HP > 0,
    has(jesse, service_weapon).

living_enemy_here(Room) :-
    location(Enemy, Room),
    atom_concat(hiss_infection_, _, Enemy),
    health(Enemy, HP),
    HP > 0,
    has(jesse, service_weapon).

/* --- Game Start --- */

start :-
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
    list_thoughts(Room),
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
    ( game_over
    -> ( parse(Tokens, restart)
       -> dispatch(restart), game_loop
       ;  parse(Tokens, quit)
       -> dispatch(quit)
       ;  normal_text("You are dead. Type 'restart' to try again or 'quit' to exit."),
          game_loop
       )
    ;  ( parse(Tokens, Command)
       -> dispatch(Command),
          ( Command = quit -> true ; game_loop )
       ;  writeln("I don't understand."),
          game_loop
       )
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
parse([attack, hiss_guard_b], attack(hiss_guard_b)).
parse([attack, hiss_brute], attack(hiss_brute)).

parse([take, Item], take(Item)).
parse([pick, up, Item], take(Item)).

parse([inventory], inventory).
parse([inv], inventory).
parse([i], inventory).

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

parse([think, Name], think(Name)).
parse([think], think(here)).
parse([place, Item], place(Item)).
parse([put, Item, down], place(Item)).
parse([put, down, Item], place(Item)).

parse([restart], restart).
parse([new, game], restart).
parse([start, over], restart).

parse([shield], shield).
parse([use, shield], shield).
parse([activate, shield], shield).

/* --- Command Dispatch --- */

dispatch(look) :- !, describe_here.
dispatch(look_at(Obj)) :- !, look_at(Obj).
dispatch(go(Dir)) :- !,
    move(jesse, Dir, Moved),
    ( game_over -> true
    ; Moved = moved -> describe_here
    ; true
    ).
dispatch(talk(ahti)) :- !, talk_to(ahti).
dispatch(talk(vendor)) :- !, talk_to(vendor).
dispatch(take(Obj)) :- !, take_item(Obj).
dispatch(inventory) :- !, show_inventory.
dispatch(attack) :-
    !,
    location(jesse, Room),
    ( living_enemy_here(Room)
    -> ( location(hiss_boss, Room), health(hiss_boss, HP0), HP0 > 0
       -> combat(jesse, hiss_boss)
       ;  location(hiss_brute, Room), health(hiss_brute, HP1), HP1 > 0
       -> combat(jesse, hiss_brute)
       ;  location(hiss_guard_b, Room), health(hiss_guard_b, HP2), HP2 > 0
       -> combat(jesse, hiss_guard_b)
       ;  location(hiss_guard, Room), health(hiss_guard, HP3), HP3 > 0
       -> combat(jesse, hiss_guard)
       ;  location(Enemy, Room), atom_concat(hiss_infection_, _, Enemy),
          health(Enemy, EHP), EHP > 0
       -> combat(jesse, Enemy)
       ;  normal_text("There's nothing to attack here.")
       )
    ;  normal_text("There's nothing to attack here.")
    ).
dispatch(attack(hiss_guard)) :- !, combat(jesse, hiss_guard).
dispatch(attack(hiss_guard_b)) :- !, combat(jesse, hiss_guard_b).
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
dispatch(think(Name)) :- !, think_thought(Name).
dispatch(place(Item)) :- !, place_item(Item).
dispatch(shield) :- !, use_shield.

dispatch(Cmd) :- format("I don't know how to handle: ~w~n", [Cmd]).

/* --- Tutorial Text --- */
show_help :-
    map_text("=== COMMANDS ==="),
    normal_text("Movement:  go north | go south | go east | go west | enter"),
    normal_text("Look:      look | look at <thing>"),
    normal_text("Map:       map | show map"),
    normal_text("Read:      read | read <note_name>"),
    normal_text("Think:     think <thought> (Jesse's inner thoughts)"),
    normal_text("Items:     take <item> | pick up <item>"),
    normal_text("Inventory: inventory | inv | i"),
    normal_text("Talk:      talk <npc>"),
    normal_text("Place:     place <item> | put <item> down"),
    normal_text("Unlock:    unlock <item> <code>"),
    normal_text("Combat:    attack <enemy>"),
    normal_text("Shield:    shield | use shield | activate shield"),
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

show_inventory :-
    findall(I, has(jesse, I), Items),
    ( Items = []
    -> highlight_text("Your inventory is empty.")
    ;  atomic_list_concat(Items, ', ', ItemStr),
       highlight_text("You are carrying:"),
       note_text(ItemStr)
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
    highlight_text("You can't leave — there's still an enemy here!"),
    findall(E-N, (
        location(E, Room),
        is_hiss_enemy(E),
        has(jesse, service_weapon),
        enemy_display_name(E, N)
    ), Pairs),
    forall(member(_-EName, Pairs), (
        format(string(ES), "Enemy spotted: ~w", [EName]),
        highlight_text(ES)
    )),
    tip_text("Defeat the enemy before moving on. Use 'attack'.").

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
    assert(location(Actor, Next)),
    ( Actor = jesse
    -> infection_check(Next)
    ; true
    ).

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
        -> ( Next = lab77_locked
           -> DisplayNext = lab77, Status = locked
           ;  DisplayNext = Next, Status = open
           )
        ;  ( clause(connected(Current, Alt, ConnDir), _), Alt \= Current
           -> ( Alt = lab77_locked
              -> DisplayNext = lab77, Status = locked
              ;  DisplayNext = Alt, Status = locked
              )
           ;  fail
           )
        )
    ;  ( clause(connected(Current, Alt, ConnDir), _)
       -> ( Alt = lab77_locked
          -> DisplayNext = lab77, Status = locked
          ;  DisplayNext = Alt, Status = locked
          )
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

    map_text(""),
    ( room_name(Current, RoomName) -> true ; RoomName = Current ),
    format(atom(LocationMsg), "Jesse is at: ~w", [RoomName]),
    map_text(LocationMsg),
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
    list_thoughts(Room),
    list_occupants(Room),
    list_items(Room),
    announce_enemies(Room).

list_occupants(Room) :-
    findall(N, (location(N, Room), N \= jesse), Others),
    ( Others = [] -> true
    ;   include(visible_npc, Others, FilteredOthers),
        ( FilteredOthers = [] -> true
        ;
          % Only show friendly NPCs here; enemies are announced via announce_enemies
          exclude(is_hiss_enemy, FilteredOthers, Friendlies),
          ( Friendlies \= [] ->
              format(string(S), "You see: ~w", [Friendlies]),
              highlight_text(S),
              ( member(ahti, Friendlies), has(jesse, service_weapon)
              -> tip_text("Tip: perhaps you could 'talk ahti' while you're here."),
                 space_if_color_changed
              ; member(vendor, Friendlies)
              -> tip_text("Tip: perhaps you could 'talk vendor' while you're here."),
                 space_if_color_changed
              ; true
              )
          ; true
          )
        )
    ).

is_hiss_enemy(hiss_guard).
is_hiss_enemy(hiss_guard_b).
is_hiss_enemy(hiss_brute).
is_hiss_enemy(hiss_boss).
is_hiss_enemy(E) :- atom_concat(hiss_infection_, _, E).

enemy_display_name(hiss_guard,   'Hiss Guard').
enemy_display_name(hiss_guard_b, 'Hiss Guard').
enemy_display_name(hiss_brute,   'Hiss Brute').
enemy_display_name(hiss_boss,    'Hiss Warden').
enemy_display_name(E, Name) :-
    atom_concat(hiss_infection_, _, E),
    Name = 'Hiss (Infection)'.

/* --- Hiss Infection System --- */

infectable_room(lobby).
infectable_room(atrium).
infectable_room(containment_hall).
infectable_room(janitor_hall).
infectable_room(upper_hall).
infectable_room(directors_office).
infectable_room(security_post).
infectable_room(records_room).
infectable_room(lab77).
infectable_room(toilets).
infectable_room(food_vendor).
infectable_room(secret_chamber).
infectable_room(death_room).

room_name(lobby,            'The Lobby').
room_name(atrium,           'The Atrium').
room_name(containment_hall, 'Containment Hall').
room_name(solitary,         'Solitary Confinement').
room_name(dylans_cell,      "Dylan's Cell").
room_name(janitor_hall,     "Janitor's Hall").
room_name(directors_office, "Director's Office").
room_name(security_post,    'Security Post').
room_name(records_room,     'Records Room').
room_name(lab77,            'Lab 77').
room_name(toilets,          'The Toilets').
room_name(food_vendor,      'Food Vendor').
room_name(secret_chamber,   'Secret Chamber').
room_name(death_room,       'The Death Room').
room_name(Room,             Room).

room_enemy_free(Room) :-
    \+ (location(Enemy, Room),
        Enemy \= jesse,
        Enemy \= ahti,
        Enemy \= vendor).

next_hiss_id(Id) :-
    aggregate_all(count, hiss_infected(_), N),
    atomic_list_concat([hiss_infection_, N], Id).

infect_room(Room) :-
    \+ hiss_infected(Room),
    assertz(hiss_infected(Room)),
    next_hiss_id(Id),
    assertz(location(Id, Room)),
    assertz(health(Id, 30)),
    room_name(Room, RoomName),
    ( location(jesse, Room)
    -> atomic_list_concat(['!! HISS INFECTION AT ', RoomName, ' — AN ENEMY HAS APPEARED HERE !!'], Alert),
       note_text(Alert)
    ;  atomic_list_concat(['[ALERT] Hiss infection detected at ', RoomName, '.'], Alert),
       note_text(Alert)
    ).

maybe_true(Prob) :-
    random(R),
    R < Prob.

maybe_infect(Room) :-
    ( \+ hiss_infected(Room),
      room_enemy_free(Room),
      maybe_true(0.2)
    -> infect_room(Room)
    ; true
    ).

infection_check(Room) :-
    ( Room = death_room
    -> assertz(game_over),
       highlight_text(""),
       highlight_text("╔═══════════════════════════════════╗"),
       highlight_text("║           GAME  OVER              ║"),
       highlight_text("╚═══════════════════════════════════╝"),
       normal_text("The Death Room claims you. Some doors should never be opened."),
       normal_text("Type 'restart' to try again.")
    ; weapon_just_taken
    -> retract(weapon_just_taken)
    ; has(jesse, service_weapon),
      infectable_room(Room)
    -> maybe_infect(Room)
    ; true
    ).

on_hiss_defeated(Room) :-
    ( hiss_infected(Room)
    -> retract(hiss_infected(Room)),
       assertz(object(health_kit, Room)),
       room_name(Room, RoomName),
       atomic_list_concat(['A health kit has appeared in ', RoomName, '!'], Msg),
       tip_text(Msg)
    ; true
    ).

/* --- Infection Combat --- */

combat(jesse, Enemy) :-
    atom_concat(hiss_infection_, _, Enemy),
    location(jesse, Room),
    location(Enemy, Room),
    has(jesse, service_weapon),
    health(Enemy, HP),
    HP > 0,
    !,
    weapon_charge(jesse, Charge),
    ( Charge =< 0
    -> highlight_text("Your weapon is out of charge! Use 'skip' to recharge.")
    ;  Dmg is 10,
       NewHP is HP - Dmg,
       retract(health(Enemy, HP)),
       assertz(health(Enemy, NewHP)),
       NewCharge is Charge - 1,
       retract(weapon_charge(jesse, Charge)),
       assertz(weapon_charge(jesse, NewCharge)),
       format(atom(Msg), "You fire at the Hiss! Enemy health: ~w -> ~w", [HP, NewHP]),
       normal_text(Msg),
       enemy_turn_infection(Enemy, Room)
    ).

combat(jesse, Enemy) :-
    atom_concat(hiss_infection_, _, Enemy),
    normal_text("That enemy is already defeated."), !.

enemy_turn_infection(Enemy, Room) :-
    health(Enemy, HP),
    ( HP =< 0
    -> highlight_text("═══════════════════════════════════"),
       highlight_text("The Hiss infection is purged!"),
       highlight_text("═══════════════════════════════════"),
       retract(location(Enemy, Room)),
       max_weapon_charge(jesse, MaxCharge),
       retract(weapon_charge(jesse, _)),
       assertz(weapon_charge(jesse, MaxCharge)),
       format(atom(RechargeMsg), "Service Weapon recharged to ~w/~w.", [MaxCharge, MaxCharge]),
       highlight_text(RechargeMsg),
       on_hiss_defeated(Room)
    ;  normal_text("The Hiss infection lashes out!"),
       ( shield_active
       -> retract(shield_active),
          highlight_text("The shield absorbs the blow! You take no damage."),
          highlight_text("The shield's barrier dissipates.")
       ;  health(jesse, JHP),
          NewJHP is JHP - 20,
          retract(health(jesse, JHP)),
          assertz(health(jesse, NewJHP)),
          max_health(jesse, MaxHP),
          format(atom(HealthMsg), "Your Health: ~w/~w", [NewJHP, MaxHP]),
          highlight_text(HealthMsg),
          weapon_charge(jesse, Charge),
          max_weapon_charge(jesse, MaxCharge),
          format(atom(ChargeMsg), "Weapon Charge: ~w/~w", [Charge, MaxCharge]),
          highlight_text(ChargeMsg),
          check_death
       )
    ).

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
         assertz(health(hiss_guard, 30)),
         assertz(weapon_just_taken),
         highlight_text("A distant screech echoes through the building...")
      ; true
      )
    ).

take_item(Item) :-
    format(atom(Msg), "There's no ~w here to take.", [Item]),
    normal_text(Msg).

look_at(cat_statue) :-
    ( has(jesse, cat_statue)
    -> normal_text("A small stone cat. It sits perfectly still in your hands. \
Its eyes seem to follow you. You get the sense it wants to be somewhere specific.")
    ;  location(jesse, Room),
       ( object(cat_statue, Room) ; cat_statue_placed, Room = atrium )
    -> normal_text("A small stone cat rests on the plinth. The floor hums softly beneath it.")
    ;  normal_text("You don't see a cat statue here.")
    ), !.

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

use_shield :-
    ( \+ has(jesse, shield)
    -> normal_text("You don't have a shield to use.")
    ;  shield_active
    -> highlight_text("Your shield is already active — it will absorb the next hit.")
    ;  location(jesse, Room),
       \+ living_enemy_here(Room)
    -> normal_text("There's no enemy here. Save the shield for when you need it.")
    ;  assertz(shield_active),
       highlight_text("You raise the hexagonal shield. A pale blue barrier crackles around you."),
       tip_text("The shield will absorb the next enemy hit, then dissipate.")
    ).

restart_game :-
    retractall(game_over),
    retractall(health_kit_tip_shown),
    retractall(attack_tip_shown),
    retractall(cat_statue_placed),
    retractall(hiss_infected(_)),
    retractall(weapon_just_taken),
    retractall(location(_, _)),
    retractall(health(_, _)),
    retractall(max_health(_, _)),
    retractall(weapon_charge(_, _)),
    retractall(max_weapon_charge(_, _)),
    retractall(has(_, _)),
    retractall(read_note(_, _)),
    retractall(outside_attempts(_)),
    retractall(object(_, _)),
    retractall(shield_active),
    assertz(location(jesse, street)),
    assertz(location(ahti, janitor_hall)),
    assertz(location(hiss_brute, atrium)),
    assertz(location(hiss_guard_b, containment_hall)),
    assertz(location(hiss_boss, solitary)),
    assertz(location(vendor, food_vendor)),
    assertz(location(dylan, dylans_cell)),
    assertz(health(jesse, 100)),
    assertz(max_health(jesse, 100)),
    assertz(weapon_charge(jesse, 10)),
    assertz(max_weapon_charge(jesse, 10)),
    assertz(health(hiss_brute, 50)),
    assertz(health(hiss_guard_b, 30)),
    assertz(health(hiss_boss, 100)),
    assertz(object(keys, lobby)),
    assertz(object(service_weapon, directors_office)),
    assertz(object(locked_box, food_vendor)),
    assertz(object(smash, lab77)),
    assertz(object(health_upgrade, secret_chamber)),
    assertz(object(health_upgrade, toilets)),
    assertz(object(charge_upgrade, atrium)),
    assertz(object(health_kit, lobby)),
    assertz(object(health_kit, security_post)),
    assertz(object(health_kit, records_room)),
    assertz(object(health_kit, containment_hall)),
    assertz(object(health_kit, solitary)),
    assertz(object(cat_statue, upper_hall)),
    assertz(object(flower, street)),
    assertz(object(shield, demolition_room)).

:- if(\+ current_module(server)).
:- initialization(start, main).
:- endif.

