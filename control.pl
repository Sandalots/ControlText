/* ============================================
      CONTROL‑STYLE TEXT ADVENTURE
      Single‑file Prolog implementation

      Inspired by Remedy Entertainment's
      CONTROL (2019). All story elements are
      an original fan adaptation.

   ── ENTITIES ────────────────────────────────
      Player: jesse
      NPCs:   ahti (janitor_hall)
              vendor (food_vendor)
              dylan (dylans_cell) — win-state NPC
      Enemies (Hiss):
              hiss_guard    — spawned in upper_hall
                              when service_weapon taken
              hiss_guard_b  — starts in containment_hall
              hiss_brute    — starts in atrium
              hiss_boss     — starts in solitary;
                              drops dylans_cell_key on death
              hiss_infection_N — dynamically spawned;
                              one per infectable room

   ── KEY ITEMS ───────────────────────────────
      keys           — unlocks upper_hall from lobby
      lab77_key      — unlocks lab77 from lobby
                       (inside locked_box at food_vendor;
                        code: BUREAU47)
      dylans_cell_key— dropped by hiss_boss
      service_weapon — main weapon; triggers hiss_guard
                       spawn and enables gated areas
      smash          — found in lab77; unlocks secret_chamber
      cat_statue     — place on atrium plinth for upgrades
      flower         — place on west_road for health_kit
      shield         — one-hit damage absorber (demolition_room)
      health_kit     — restores HP to max
      health_upgrade — +5 max HP and current HP
      charge_upgrade — +2 max weapon charge and current charge
      locked_box     — unlockable container at food_vendor
      weapon_form    — found in resonance_lab; triples weapon
                       damage but costs 3 charges per shot
      charge_upgrade — also found in sub_lab (west of resonance_lab,
                       requires smash)

   ── ARCHITECTURE ────────────────────────────
      This file is designed to run in two modes:
        Standalone — consulted directly in SWI‑Prolog;
                     output predicates (color_ln, normal_text
                     etc.) use ansi_format/3 for the terminal.
        Web server — loaded by server.pl via :- [control];
                     output predicates are overridden before
                     loading so all text is buffered as JSON
                     for the browser front‑end (index.html).
      The :- if(\+ current_module(server)) guard in the
      OUTPUT PREDICATES section handles the split.

   ── EXECUTION FLOW ──────────────────────────
      Standalone: initialization(start, main)
        start/0 → show_map, describe, game_loop
        game_loop/0 → read line → parse/2 → dispatch/1
                    → recurse (or halt on quit/game_over)
      Web server: handle_start / handle_command
        → reset_game / init_game_output
        → parse(Tokens, Command) → dispatch(Command)
        → buf_flush(Lines) → reply_json_dict

   ── COLOUR SCHEME ───────────────────────────
        cyan    — map / room headers / HUD lists
        green   — narrative descriptions
        yellow  — highlights, combat results, status
        magenta — tips / hints
        red     — NPC speech, notes, alerts
   ============================================ */

/* ============================================
      DYNAMIC DECLARATIONS
      All mutable state is declared here so
      the file can be cleanly consulted/reloaded.

      Naming conventions:
        location(Entity, Room)   — where something is
        health(Entity, HP)       — current hit points
        max_health(Entity, MaxHP)— upper HP ceiling
        has(Entity, Item)        — inventory membership
        object(Item, Room)       — item lying in a room
        weapon_charge(E, C)      — current shoot charges
        max_weapon_charge(E, MC) — charge ceiling
        read_note(Room, NoteId)  — marks a note as read
        hiss_infected(Room)      — room has live infection
        outside_attempts(N)      — how many times Jesse
                                   tried to wander off
      One-shot flags (no payload):
        game_over              — set on death or win
        health_kit_tip_shown   — first-kill tip guard
        attack_tip_shown       — first-enemy tip guard
        weapon_just_taken      — suppresses infection on
                                 the turn the weapon is
                                 picked up (one-shot)
        cat_statue_placed      — plinth puzzle complete
        shield_active          — next hit is absorbed
        weapon_form_active     — weapon form acquired;
                                 3× damage / 3-charge cost
   ============================================ */

:- dynamic location/2.          % location(Entity, Room)
:- dynamic health/2.            % health(Entity, HP)
:- dynamic max_health/2.        % max_health(Entity, MaxHP)
:- dynamic has/2.               % has(Entity, Item)
:- dynamic read_note/2.         % read_note(Room, NoteId)
:- dynamic object/2.            % object(Item, Room)
:- dynamic weapon_charge/2.     % weapon_charge(Entity, Charge)
:- dynamic max_weapon_charge/2. % max_weapon_charge(Entity, MaxCharge)
:- dynamic last_color/1.        % last_color(Color) — for blank-line spacing
:- dynamic game_over/0.         % asserted when player dies or wins
:- dynamic health_kit_tip_shown/0. % one-shot: "look for health kits" tip
:- dynamic attack_tip_shown/0.     % one-shot: "use attack" tip on first enemy sight
:- dynamic hiss_infected/1.     % hiss_infected(Room) — room has active infection
:- dynamic weapon_just_taken/0. % one-shot: suppresses infection on weapon-pickup turn
:- dynamic cat_statue_placed/0. % one-shot: plinth puzzle has been solved
:- dynamic shield_active/0.     % one-shot: next enemy hit is fully absorbed
:- dynamic weapon_form_active/0. % persistent: weapon form taken; 3× damage, 3-charge cost
:- dynamic sense_active/0.      % persistent: paranatural sense item taken; reveals adjacent enemies
:- dynamic outside_attempts/1.  % outside_attempts(N) — escalating flavour counter

:- discontiguous take_enemy_hit/1.
:- discontiguous check_death/0.
:- discontiguous fire_weapon/2.
:- discontiguous combat/2.
:- discontiguous enemy_turn/0.
:- discontiguous enemy_turn_spawn/0.
:- discontiguous enemy_turn_guard_b/0.
:- discontiguous enemy_turn_brute/0.
:- discontiguous enemy_turn_boss/0.
:- discontiguous enemy_turn_infection/2.

:- use_module(library(pcre)).       % re_match/2, re_replace/4
:- use_module(library(ansi_term)).  % ansi_format/3

/* ============================================
      INPUT HELPERS
      Token cleaning for the parser.
   ============================================ */

%% clean_token_smart(+In, -Out)
%  Keeps alphanumeric codes intact (e.g. bureau47);
%  strips leading/trailing punctuation from plain words.
clean_token_smart(In, Out) :-
    ( re_match('[a-z]+[0-9]|[0-9]+[a-z]'/i, In)
    -> Out = In
    ;  clean_token(In, Out)
    ).

%% clean_token(+In, -Out)
%  Strips any non‑letter characters from the start and end of a token.
clean_token(In, Out) :-
    re_replace('(^[^a-z]+|[^a-z]+$)'/i, '', In, Out).

/* ============================================
      OUTPUT PREDICATES
      Colour-coded terminal output.
      Defined only in standalone mode — when
      loaded by server.pl these are provided
      by the server module instead.
   ============================================ */

:- if(\+ current_module(server)).

%% last_color/1 — tracks the most recently used output colour.
%  A blank line is inserted automatically when the colour changes,
%  to visually separate output blocks.
last_color(default).

%% color_ln(+Color, +Text)
%  Print Text in the given ANSI Color; insert blank line on colour change.
color_ln(Color, Text) :-
    ( last_color(LastColor) -> true ; LastColor = default ),
    ( LastColor \= Color, LastColor \= default -> writeln("") ; true ),
    ansi_format([fg(Color)], '~w~n', [Text]),
    retractall(last_color(_)),
    assert(last_color(Color)).

%% space_if_color_changed
%  Emit a blank line if ANY colour other than default has been used.
%  Useful as an explicit separator between output sections.
space_if_color_changed :-
    last_color(LastColor),
    ( LastColor \= default -> writeln("") ; true ).

%% normal_text(+Text)   — green: narrative prose
normal_text(Text) :-
    ( last_color(LastColor) -> true ; LastColor = default ),
    ( LastColor \= green, LastColor \= default -> writeln("") ; true ),
    ansi_format([fg(green)], '~w~n', [Text]),
    retractall(last_color(_)),
    assert(last_color(green)).

%% highlight_text(+Text) — yellow: status, combat results, HUD info
highlight_text(Text) :-
    ( last_color(LastColor) -> true ; LastColor = default ),
    ( LastColor \= yellow, LastColor \= default -> writeln("") ; true ),
    ansi_format([fg(yellow)], '~w~n', [Text]),
    retractall(last_color(_)),
    assert(last_color(yellow)).

%% map_text(+Text) — cyan: map, room location header, room lists
map_text(Text) :-
    ( last_color(LastColor) -> true ; LastColor = default ),
    ( LastColor \= cyan, LastColor \= default -> writeln("") ; true ),
    ansi_format([fg(cyan)], '~w~n', [Text]),
    retractall(last_color(_)),
    assert(last_color(cyan)).

%% tip_text(+Text) — magenta bold: gameplay hints
tip_text(Text) :-
    ( last_color(LastColor) -> true ; LastColor = default ),
    ( LastColor \= magenta, LastColor \= default -> writeln("") ; true ),
    ansi_format([fg(magenta), bold], '~w~n', [Text]),
    retractall(last_color(_)),
    assert(last_color(magenta)).

%% speak(+Who, +Text) — red italic: NPC dialogue
speak(ahti,   Text) :- ansi_format([fg(red), italic], '~w~n', [Text]).
speak(vendor, Text) :- ansi_format([fg(red), italic], '~w~n', [Text]).
speak(dylan,  Text) :- ansi_format([fg(red), italic], '~w~n', [Text]).
speak(_,      Text) :- normal_text(Text).

%% note_text(+Text) — red italic: readable notes and alerts
note_text(Text) :-
    ansi_format([fg(red), italic], '~w~n', [Text]).

:- endif.

/* ============================================
      NPC VISIBILITY
      Determines which entities are shown when
      listing room occupants via list_occupants/1.

      Friendly NPCs (ahti, vendor, dylan) are
      always visible.  Hiss enemies are hidden
      until Jesse acquires the Service Weapon —
      before that point the player cannot see
      or interact with them at all.
   ============================================ */

visible_npc(ahti).
visible_npc(vendor).
visible_npc(dylan).
visible_npc(drenchtov).
visible_npc(hartwell).
visible_npc(okoro).
visible_npc(E) :-
    is_hiss_enemy(E),
    has(jesse, service_weapon).

/* ============================================
      ENEMY HELPERS
      Utility predicates shared by combat,
      visibility, movement blocking, and the
      map display.
   ============================================ */

%% is_hiss_enemy(+Entity)
%  True for all named Hiss enemy types and dynamically spawned
%  infection entities.  Infection atoms follow the pattern
%  hiss_infection_N (e.g. hiss_infection_0, hiss_infection_1).
%  Used by visible_npc/1, list_occupants/1, and movement guards.
is_hiss_enemy(hiss_guard).
is_hiss_enemy(hiss_guard_b).
is_hiss_enemy(hiss_spawn).
is_hiss_enemy(hiss_brute).
is_hiss_enemy(hiss_boss).
is_hiss_enemy(E) :- atom_concat(hiss_infection_, _, E).

%% enemy_display_name(+Entity, -Name)
%  Human-readable name used in combat announcements and the HUD.
%  hiss_guard and hiss_guard_b share the same display name.
enemy_display_name(hiss_guard,   'Hiss Guard').
enemy_display_name(hiss_guard_b, 'Hiss Guard').
enemy_display_name(hiss_spawn,   'Hiss Spawn').
enemy_display_name(hiss_brute,   'Hiss Brute').
enemy_display_name(hiss_boss,    'Hiss Warden').
enemy_display_name(E, 'Hiss (Infection)') :-
    atom_concat(hiss_infection_, _, E).

%% living_enemy_here(+Room)
%  Succeeds if there is at least one Hiss enemy in Room that:
%    • is currently alive (HP > 0), AND
%    • is visible (Jesse has the Service Weapon).
%  There is one clause per possible named enemy, plus a general
%  clause for dynamically spawned infection entities.
%  Used by move/3 to block room exits during combat, and by
%  dispatch(attack) to resolve the correct target.
living_enemy_here(Room) :-
    location(hiss_guard, Room),
    health(hiss_guard, HP), HP > 0,
    has(jesse, service_weapon).

living_enemy_here(Room) :-
    location(hiss_spawn, Room),
    health(hiss_spawn, HP), HP > 0,
    has(jesse, service_weapon).

living_enemy_here(Room) :-
    location(hiss_guard_b, Room),
    health(hiss_guard_b, HP), HP > 0,
    has(jesse, service_weapon).

living_enemy_here(Room) :-
    location(hiss_brute, Room),
    health(hiss_brute, HP), HP > 0,
    has(jesse, service_weapon).

living_enemy_here(Room) :-
    location(hiss_boss, Room),
    health(hiss_boss, HP), HP > 0,
    has(jesse, service_weapon).

living_enemy_here(Room) :-
    location(Enemy, Room),
    atom_concat(hiss_infection_, _, Enemy),
    health(Enemy, HP), HP > 0,
    has(jesse, service_weapon).

%% announce_enemies(+Room)
%  Print a "Enemy spotted" line for each live enemy in the room.
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

/* ============================================
      INITIAL STATE
      Locations, health and stats at game start.
      Items are listed separately below.
      hiss_guard is spawned dynamically when
      the Service Weapon is picked up.
   ============================================ */

:- assertz(location(jesse,        street)).
:- assertz(location(ahti,         janitor_hall)).
:- assertz(location(drenchtov,    utility_bay)).
:- assertz(object(health_kit,     utility_bay)).
:- assertz(location(hiss_brute,   atrium)).
:- assertz(location(hiss_guard_b, containment_hall)).
:- assertz(location(hiss_boss,    solitary)).
:- assertz(location(vendor,       food_vendor)).
:- assertz(location(dylan,        dylans_cell)).

:- assertz(health(jesse,        100)).
:- assertz(max_health(jesse,    100)).
:- assertz(health(hiss_brute,    50)).
:- assertz(health(hiss_guard_b,  30)).
:- assertz(health(hiss_boss,    100)).

:- assertz(weapon_charge(jesse,     10)).
:- assertz(max_weapon_charge(jesse, 10)).

:- assertz(outside_attempts(0)).

/* ============================================
      STATIC ITEMS
      Initial object placement at game start.
      Additional items can be asserted at
      runtime (e.g. dylans_cell_key after boss).
   ============================================ */

:- assertz(object(keys,           lobby)).
:- assertz(object(service_weapon, directors_office)).
:- assertz(object(health_kit,     anteroom)).
:- assertz(object(health_upgrade, ops_room)).
:- assertz(object(locked_box,     food_vendor)).
:- assertz(object(health_kit,     north_alley)).
:- assertz(object(smash,          lab77)).
:- assertz(object(health_kit,     archive_bay)).
:- assertz(object(health_upgrade, secret_chamber)).
:- assertz(object(health_upgrade, toilets)).
:- assertz(object(charge_upgrade, pipe_room)).
:- assertz(object(health_kit,     lobby)).
:- assertz(location(okoro,        lab77)).
:- assertz(object(health_kit,     security_post)).
:- assertz(object(health_kit,     records_room)).
:- assertz(object(sense,          records_room)).
:- assertz(object(health_kit,     containment_hall)).
:- assertz(object(charge_upgrade, cell_annex)).
:- assertz(object(health_kit,     watch_post)).
:- assertz(object(health_kit,     solitary)).
:- assertz(object(charge_upgrade, atrium)).
:- assertz(object(health_kit,     rejuvenation_room)).
:- assertz(object(health_upgrade, rejuvenation_room)).
:- assertz(object(charge_upgrade, sub_lab)).
:- assertz(object(weapon_form,    resonance_lab)).
:- assertz(object(cat_statue,     upper_hall)).
:- assertz(object(flower,         street)).
:- assertz(object(shield,         demolition_room)).
:- assertz(object(health_kit,     blast_corridor)).
:- assertz(object(charge_upgrade, evidence_vault)).
:- assertz(location(hartwell,     demolition_room)).

/* ============================================
      MAP — connected(From, To, Direction)
      Unconditional facts use plain clauses.
      Conditional connections (locked behind
      items) use rule bodies.
   ============================================ */

/* --- Street / entrance --- */
connected(street,      lobby,       enter).
connected(street,      lobby,       north).
connected(lobby,       street,      exit).
connected(lobby,       street,      south).
connected(street,      food_vendor, east).
connected(food_vendor, street,      west).
connected(food_vendor, north_alley, north).
connected(north_alley, food_vendor, south).
connected(food_vendor, east_plaza,  east).
connected(east_plaza,  food_vendor, west).
connected(food_vendor, south_lot,   south).
connected(south_lot,   food_vendor, north).
connected(street,      west_road,   west).
connected(west_road,   street,      east).

/* --- Lobby branches --- */
connected(lobby,        janitor_hall, east).
connected(janitor_hall, lobby,        west).
connected(janitor_hall, toilets,      north).
connected(toilets,      janitor_hall, south).
connected(toilets,      pipe_room,    north) :- has(jesse, smash).
connected(pipe_room,    toilets,      south) :- has(jesse, smash).
connected(janitor_hall, utility_bay,  south).
connected(utility_bay,  janitor_hall, north).

/* --- Atrium / containment — requires Service Weapon --- */
connected(janitor_hall,     atrium,             east) :- has(jesse, service_weapon).
connected(atrium,           janitor_hall,       west) :- has(jesse, service_weapon).
connected(atrium,            containment_hall,   east) :- has(jesse, service_weapon).
connected(containment_hall,  atrium,             west) :- has(jesse, service_weapon).
connected(containment_hall,  cell_annex,         north) :- has(jesse, service_weapon).
connected(cell_annex,        containment_hall,   south) :- has(jesse, service_weapon).
connected(containment_hall,  watch_post,         south) :- has(jesse, service_weapon).
connected(watch_post,        containment_hall,   north) :- has(jesse, service_weapon).
connected(atrium,           rejuvenation_room,  north) :- has(jesse, service_weapon).
connected(rejuvenation_room, atrium,            south) :- has(jesse, service_weapon).

/* --- Resonance Lab — requires Service Weapon --- */
connected(atrium,        resonance_lab, south) :- has(jesse, service_weapon).
connected(resonance_lab, atrium,        north) :- has(jesse, service_weapon).

/* --- Solitary — requires Service Weapon --- */
connected(containment_hall, solitary,         east) :- has(jesse, service_weapon).
connected(solitary,         containment_hall, west) :- has(jesse, service_weapon).

/* --- Dylan's Cell — requires dylans_cell_key (dropped by boss) --- */
connected(solitary,    dylans_cell, east) :- has(jesse, dylans_cell_key).
connected(dylans_cell, solitary,    west) :- has(jesse, dylans_cell_key).

/* --- Upper hall — requires keys (found in lobby) --- */
connected(lobby,            upper_hall,       north) :- has(jesse, keys).
connected(upper_hall,       lobby,            south).
connected(upper_hall,       directors_office, north).
connected(directors_office, upper_hall,       south).
connected(upper_hall,       security_post,    east).
connected(security_post,    upper_hall,       west).
connected(upper_hall,       records_room,     west).
connected(records_room,     upper_hall,       east).

/* --- Director's office north wing --- */
connected(directors_office, demolition_room,  north).
connected(demolition_room,  directors_office, south).
connected(demolition_room,  death_room,       north).
connected(death_room,       demolition_room,  south).

/* --- Blast Corridor & Evidence Vault — flanking the Demolition Room --- */
connected(demolition_room, blast_corridor,  west).
connected(blast_corridor,  demolition_room, east).
connected(demolition_room, evidence_vault,  east).
connected(evidence_vault,  demolition_room, west).

/* --- Anteroom & Ops Room — flanking the Director's office --- */
connected(directors_office, anteroom, west).
connected(anteroom,         directors_office, east).
connected(directors_office, ops_room, east).
connected(ops_room,         directors_office, west).

/* --- Lab 77 — locked/unlocked depending on lab77_key --- */
connected(lobby,        lab77_locked, west) :- \+ has(jesse, lab77_key).
connected(lab77_locked, lobby,        east) :- \+ has(jesse, lab77_key).
connected(lobby,        lab77,        west) :-   has(jesse, lab77_key).
connected(lab77,        lobby,        east) :-   has(jesse, lab77_key).

/* --- Archive Bay — west of Lab 77, no gate --- */
connected(lab77,        archive_bay, west).
connected(archive_bay,  lab77,       east).

/* --- Secret chamber — requires smash object --- */
connected(lab77,          secret_chamber, south) :- has(jesse, smash).
connected(secret_chamber, lab77,          north) :- has(jesse, smash).

/* --- Sub-Lab — west of resonance_lab, requires smash --- */
connected(resonance_lab, sub_lab,        west) :- has(jesse, smash).
connected(sub_lab,       resonance_lab,  east) :- has(jesse, smash).

/* ============================================
      ROOM DESCRIPTIONS
      Displayed on entry and with 'look'.
   ============================================ */

description(street,
    "You stand outside the Federal Bureau of Control. The building is tall, \
featureless, and humming faintly. The front doors wait silently.").

description(food_vendor,
    "A greasy hot‑dog cart stands here. A man in a stained apron shouts, \
'Best dogs in the Oldest House!'").

description(north_alley,
    "A narrow service alley running behind the Oldest House. \
The building's back wall looms overhead — raw concrete, no windows, \
stained grey by decades of city weather. \
A metal service door stands shut at the far end. \
Cigarette butts cluster near a ventilation grate: evidence of every smoke break \
taken by Bureau staff who needed a moment outside and couldn't go far.").

description(east_plaza,
    "A wide concrete apron stretching east of the hot-dog cart. \
There are benches — Bureau-standard, uncomfortable by design. \
A flagpole at the far edge still flies a Bureau pennant, intact, \
calmly snapping in the wind as if nothing has happened. \
Something about that is worse than if it had come down.").

description(south_lot,
    "Staff parking. Bureau-issue signage: PERMIT HOLDERS ONLY. \
The lot is almost full — maybe thirty cars sitting in orderly rows, \
each left as if its owner planned to come back after lunch. \
A glass security booth at the entrance stands empty, \
a half-drunk coffee visible on the counter inside. \
Nobody came back after lunch.").

description(west_road,
    "A quiet side street veering north. The air smells like dust and old paper. \
There's not much here.").

description(lobby,
    "A vast lobby with humming lights. A janitor's cart sits alone.").

description(janitor_hall,
    "A narrow hallway. Ahti leans on his mop, watching you.").

description(utility_bay,
    "A cramped maintenance bay south of the hallway. \
Shelves of cleaning supplies line the walls — mop heads, bleach drums, labelled bins. \
A Bureau-issue safety notice board hangs lopsided above a folding table. \
Sitting at the table, eating a sandwich and reading a form in triplicate, \
is a man in a Bureau lanyard. He looks up at you with the calm expression \
of someone who has decided that if he just keeps filling in forms, \
everything will eventually resolve itself.").

description(toilets,
    "A dimly lit bathroom. The smell of industrial cleaner hangs in the air. \
A first aid kit sits on the counter, weathered and faded.").

description(pipe_room,
    "A utility void above the bathroom ceiling, barely tall enough to stand in. \
Branching pipes run the length of the room, lagged with crumbling insulation. \
The smash object opened a section of false wall to get you in here — \
the hole it left is ragged and clean, like a bite through cardboard. \
Something was stored here deliberately, shoved behind a pipe and wrapped in a Bureau evidence bag: \
a compact resonance capacitor, still charged.").

description(atrium,
    "A vast circular chamber with high vaulted ceilings. Strange geometric patterns \
cover the floor, seeming to shift and breathe with an otherworldly rhythm. \
The air feels heavy with presence.").

description(rejuvenation_room,
    "A low, quiet room off the north side of the atrium. \
The walls are tiled in pale green ceramic, the grout still clean. \
Recessed lighting hums at a frequency that feels deliberately calibrated — \
not quite warm, not quite clinical, but something in between. \
A row of reclining examination chairs faces a bank of monitoring equipment, \
most of it still active. Drip lines hang from chrome stands, untouched. \
The room smells faintly of something medicinal and something older than medicine. \
You feel marginally better just standing in it.").

description(resonance_lab,
    "A disused research lab buried behind the atrium. The walls are lined with \
blackboards covered in resonance equations, half-erased and restless. \
In the centre of the room, on a scorched examination table, sits a shifting \
mass of paranatural energy barely contained in the form of a weapon. \
The air hums with potential violence.").

description(sub_lab,
    "A cramped auxiliary lab, sealed off from the resonance chamber by a reinforced \
wall — something punched a hole through it from the other side at some point. \
The breach is still there, jagged and cold. \
Inside: overturned equipment, a shattered monitor, and on a high shelf, \
a Bureau-issue resonance capacitor, still charged. \
Somehow the whole room just missed the worst of whatever happened here.").

description(containment_hall,
    "A long reinforced corridor. Containment cells line both walls, most of them \
hanging open and dark. The air smells of ozone and fear. A Hiss‑infected guard \
patrols the far end, twitching erratically.").

description(cell_annex,
    "A processing annex off the north side of the containment hall. \
This is where inmates were booked, documented, and assigned cells. \
A long counter runs the length of one wall, clipboards still hanging above it, \
each labelled with a cell number. The cell numbers go higher than the hall has cells. \
A locked filing cabinet has been forced open, its contents spread across the floor. \
Someone was looking for a specific name. \
From the mess, it looks like they found it.").

description(watch_post,
    "A raised observation room that looks back down into the containment hall \
through scratched reinforced glass. Banks of monitors show static on most channels \
and nothing on the rest. \
One screen still has a live feed from a camera in solitary: a fixed angle, \
a corridor, a shape at the far end that hasn't moved in however long this tape has been running. \
A chair has been bolted to the floor facing the monitors. \
Somebody had to watch that screen every shift. \
You think about what that job was like.").

description(solitary,
    "A cavernous solitary confinement block. The cells here are reinforced with \
paranatural dampeners — thick runes etched into every surface. Most of the doors \
have been torn clean off their hinges from the inside. \
At the far end of the block, something massive stands perfectly still, \
facing the wall. It turns slowly as you enter. \
The Hiss Warden. It was left here to guard something. Or someone.").

description(dylans_cell,
    "A small reinforced cell, stripped bare. A single cot. A single light. \
Dylan sits on the edge of the cot, head in his hands. \
He looks up when you enter. His eyes are red‑rimmed, exhausted — \
but they're his eyes. Not the Hiss. Not whatever you were afraid you'd find. \
Just your brother. He stares at you for a long moment. Then he says your name.").

description(upper_hall,
    "A long corridor leading deeper into the Bureau. The air hums with a faint \
paranatural resonance. Doors line the walls, some hanging open, others sealed tight.").

description(security_post,
    "A small security post. Monitors flicker with static. An overturned chair \
suggests someone left in a hurry. A first aid kit sits on the desk.").

description(records_room,
    "A dusty records room. Filing cabinets line the walls, many hanging open \
and emptied. The smell of old paper fills the air. \
A first aid kit sits on a shelf, untouched.").

description(directors_office,
    "A quiet office bathed in pale light. The Director slumps behind the desk, \
a single bullet wound to the temple. In his outstretched hand — the Service Weapon. \
It hums faintly, as if waiting. Whatever drove him to this end, the weapon \
chose to stay. Pick it up. You'll need it.").

description(anteroom,
    "A small private waiting room adjoining the Director's office. \
Two leather chairs face each other across a low table, undisturbed. \
A glass of water on the table is still full. \
Whoever poured it never came back in. \
Hanging on the wall: a framed Bureau charter, a commendation plaque, \
and a photograph of a team of people none of whom appear to have faces.").

description(ops_room,
    "The Director's operational command post. Unlike the main office, this room \
was clearly used right up until the end — papers everywhere, monitors still running, \
an open radio crackling with static. \
A tactical map of the Oldest House covers one wall, annotated in red. \
Some of the annotations don't match any room you've been in yet.").

description(lab77_locked,
    "A sealed laboratory door marked 'LAB 77' blocks your path. It's locked tight.").

description(lab77,
    "Inside Lab 77. Equipment hums softly on the walls. A smash object sits on a bench.").

description(archive_bay,
    "A long storage bay running west behind Lab 77. Metal shelving units line \
the walls, loaded with sealed specimen crates and bound Bureau document files — \
most of them labelled in a shorthand that no longer means anything. \
The lights still flicker on. A first aid kit sits near the door, untouched.").

description(secret_chamber,
    "A hidden chamber behind a crumbled wall. Strange equipment covers the shelves. \
Your brother sits slumped in a chair, eyes closed.").

description(demolition_room,
    "A ruined chamber, walls blasted inward as if by some enormous force. \
Debris litters the floor. In the centre, hovering inches above a scorched pedestal, \
a translucent hexagonal shield pulses with a pale blue light. \
An Object of Power. It knows you're here.").

description(blast_corridor,
    "A service corridor running west from the demolition site. \
The blast damage is worse here — the walls buckled inward, the ceiling cracked open, \
and the floor is carpeted with powdered concrete and shattered glass. \
Something large came through here in a hurry. \
Or something large was pushed.").

description(evidence_vault,
    "A sealed archive room off the east side of the demolition chamber. \
Heavy blast doors have warped in their frame but held — the room inside is \
roughly intact. Metal shelving holds rows of sealed Bureau evidence canisters, \
each labelled with a case number. \
A single workbench in the centre holds an open canister and a half-written report. \
Whoever was working here left without finishing the sentence.").

description(death_room,
    "The air tears open. A wall of pure resonant noise hits you like a physical blow. \
The Hiss is not here — the Hiss IS here, everywhere, in every atom of the room. \
You had one second to reconsider. You didn't take it.").

/* ============================================
      ROOM NAMES
      Display names used in the map and messages.
      The final clause is a fallback that returns
      the room atom unchanged.
   ============================================ */

room_name(street,           'The Street').
room_name(lobby,            'The Lobby').
room_name(atrium,              'The Atrium').
room_name(rejuvenation_room,   'Rejuvenation Room').
room_name(resonance_lab,       'Resonance Lab').
room_name(sub_lab,          'Sub-Lab').
room_name(containment_hall, 'Containment Hall').
room_name(cell_annex,       'Cell Annex').
room_name(watch_post,       'Watch Post').
room_name(solitary,         'Solitary Confinement').
room_name(dylans_cell,      "Dylan's Cell").
room_name(janitor_hall,     "Janitor's Hall").
room_name(utility_bay,      'Utility Bay').
room_name(directors_office, "Director's Office").
room_name(anteroom,         'Anteroom').
room_name(ops_room,         'Ops Room').
room_name(security_post,    'Security Post').
room_name(records_room,     'Records Room').
room_name(lab77,            'Lab 77').
room_name(lab77_locked,     'Lab 77 (Locked)').
room_name(archive_bay,      'Archive Bay').
room_name(toilets,          'The Toilets').
room_name(pipe_room,        'Pipe Room').
room_name(food_vendor,      'Food Vendor').
room_name(north_alley,      'North Alley').
room_name(east_plaza,       'East Plaza').
room_name(south_lot,        'South Lot').
room_name(west_road,        'West Road').
room_name(secret_chamber,   'Secret Chamber').
room_name(demolition_room,  'Demolition Room').
room_name(blast_corridor,   'Blast Corridor').
room_name(evidence_vault,   'Evidence Vault').
room_name(death_room,       'The Death Room').
room_name(Room,              Room).  % fallback — return atom as-is

/* ============================================
      NOTES — note(Room, Id, Text)
      Static lore and environmental storytelling.
      Players use 'read <Id>' to read them.
   ============================================ */

note(street, welcome,
    "A faded government memo: 'The Bureau never sleeps. Neither should you.'").
note(street, construction,
    "Public Notice: There will be noisy construction in this area for some time. \
We thank you for your cooperation and patience during these improvements.").

note(west_road, old_sign,
    "A weathered street sign, half-obscured by vines: 'Dimensional Research Wing - 2 miles.'").
note(west_road, graffiti,
    "Cryptic graffiti scratched into a brick wall: 'The House changes. Don't let it change you.'").
note(west_road, lost_time,
    "A discarded pocket watch lies in the dirt. The hands spin wildly, unable to settle on a time.").

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

note(food_vendor, menu,
    "A grease-stained menu board reads: 'TODAY'S SPECIAL: Bureau Burger - Code: BUREAU47'").

note(north_alley, back_graffiti,
    "Spray-painted on the service door in confident capitals: 'BUREAU EATS PIGEONS.' \
Below it, in much smaller and more careful letters, someone has written: \
'This is defamatory. The Bureau has never eaten any pigeons. \
— Internal Affairs, Informal Capacity.' \
Below that, in the original hand: 'PROVE IT.'").
note(north_alley, smoke_break_note,
    "On the back of a Bureau memo, written in the cramped script of someone \
who had about four minutes and a cigarette: \
'Day 47. Still can't get the filing system to register objects with no fixed form. \
IT says it's a data entry issue. IT has clearly never tried to file something \
that is also filing you back. Went for a smoke. Better out here. \
Smell of outside is good. — B.'").
note(north_alley, service_door_notice,
    "A laminated Bureau notice riveted to the service door: \
'ALL DELIVERIES: Sign in at front desk. Do not leave items unattended. \
Do not make eye contact with any item that appears to be watching you. \
Report anomalous deliveries to your supervisor immediately. \
If your supervisor is the anomalous delivery, refer to Pamphlet 12.' \
Pamphlet 12 is not attached.").

note(east_plaza, bureau_flag,
    "The Bureau pennant on the flagpole is regulation-issue: \
dark grey, a stylised pyramid, no text. \
It's been up there for years — you can tell by the precise fading at the edges. \
Whoever runs the building maintenance had it replaced on a schedule. \
Right now, on schedule or not, it's still there. \
The Bureau, at least on a flag, still stands.").
note(east_plaza, abandoned_placard,
    "A hand-lettered protest sign lying face-up on one of the benches: \
'WE DEMAND TRANSPARENCY — WHAT IS INSIDE THE OLDEST HOUSE??' \
The cardboard is slightly damp. It wasn't here long before whoever carried it \
had to put it down and leave in a hurry. \
You consider the question. You are inside the Oldest House. \
You do not feel particularly transparent.").

note(south_lot, parking_permit,
    "A Bureau parking permit left on the dash of a grey sedan: \
'VALID: FY26. HOLDER: TRENCH, Z. CLEARANCE: LEVEL 4.' \
The permit has been renewed every year for at least a decade. \
The same car, same space, same permit. Ten years of Tuesday mornings. \
Director Trench parked here this morning and walked into the building \
and did not walk out again.").
note(south_lot, security_rota,
    "The staff rota pinned inside the security booth, \
visible through the glass: eight names, three shifts, \
all crossed through with a single diagonal red line \
and the word SUSPENDED stamped in bureaucratic red. \
At the bottom, in handwriting: 'No point. Nobody's leaving. — Gate'").

note(janitor_hall, ahti_notice,
    "A notice pinned above Ahti's cart in careful block letters: \
'MON: Mop level 2. TUE: Mop level 2. WED: Mop level 2. \
Every day the same. Routine is how we survive here. —A'").

note(utility_bay, safety_board,
    "The Bureau safety notice board. Most of it is standard: \
'REPORT ALL PARANATURAL INCIDENTS TO YOUR LINE MANAGER.' \
'OBJECTS OF INTEREST: DO NOT TOUCH UNLESS CLEARED.' \
'HISS EXPOSURE: SEE PAMPHLET 7C.' \
Pamphlet 7C is not attached. Someone wrote in biro: 'ASK DRENCHTOV.' \
Drenchtov has apparently written back: 'DON'T ASK DRENCHTOV.'").
note(utility_bay, supply_request,
    "A Bureau supply requisition form in triplicate, mostly filled in: \
'Item requested: (1) mop head, standard. (1) bleach, industrial. \
(1) personnel extraction — high priority.' \
The last line has been crossed out and rewritten four times. \
Above it, in neat capitals: \
'I AM AWARE THIS IS NOT A STANDARD SUPPLY REQUEST. PLEASE ADVISE. —Drenchtov'").
note(utility_bay, evacuation_memo,
    "A Bureau all-staff memo, rubber-stamped CONFIDENTIAL: \
'BUILDING EVACUATION: All non-essential personnel are advised to proceed \
to the designated rally point at their earliest convenience.' \
Scrawled across the bottom: 'Conveniently, I cannot locate the rally point. \
Conveniently, I cannot locate any personnel. \
Conveniently, I have a sandwich. I will wait here. —D'").

note(toilets, mirror_message,
    "Written in soap across the bathroom mirror, large unsteady letters: \
'THEY ARE IN THE WALLS. IF YOU CAN READ THIS YOU ARE STILL YOU. STAY THAT WAY.'").

note(pipe_room, stashed_memo,
    "Tucked inside the evidence bag with the capacitor, a folded Bureau memo: \
'If you're reading this, you found the gap in the wall. Good. \
That means you have the object and you know what you're doing. \
The capacitor in here adds to your weapon's maximum charge. \
I hid it because I didn't want certain colleagues knowing how far \
the resonance experiments had progressed. \
If I'm not around to explain: it was further than they thought. — Dr. V'").

note(atrium, cat_plinth,
    "A circular stone plinth sits at the centre of the atrium floor. \
An inscription reads: 'The Watcher returns the way.' \
A shallow recess on top looks like something should rest there.").

note(rejuvenation_room, protocol_board,
    "A laminated Bureau protocol sheet mounted beside the entrance: \
'REJUVENATION SUITE — AUTHORISED PERSONNEL ONLY. \
Residential resonance frequency: 7.83 Hz (calibrated). \
Biological enhancement window: 20–40 minutes per session. \
Note: extended exposure above 90 minutes has produced anomalous results in \
three (3) subjects. Report any involuntary structural changes to your supervisor.' \
At the bottom: 'What does involuntary structural changes mean? — L.' \
Above: 'It means don't stay too long. — anonymous'").
note(rejuvenation_room, research_summary,
    "A bound research summary left open on the monitoring desk: \
'Project BLOOM — Paranatural Bioregeneration: Year Two.' \
The abstract reads: 'Subjects exposed to calibrated resonance fields \
demonstrate accelerated tissue repair, elevated immune response, and in three cases, \
complete reversal of chronic injury. \
Mechanism remains unclear. The building appears to want subjects healthy. \
The building's motivations in this matter are not fully understood \
but are, so far, not adverse. Proceed with cautious optimism. — Project Lead'").
note(rejuvenation_room, session_log,
    "A handwritten session log clipped to one of the examination chairs: \
'Day 1: Standard headache, gone by hour two. \
Day 3: Old shoulder injury — the one from the car accident in 2019 — \
completely undetected at scan. \
Day 7: Dr V asked me to stop logging this. I'm continuing privately. \
Whatever this room is doing, it's doing it on purpose. \
The building knows I'm in here. I can feel it noticing. — Subject 4'").
note(atrium, geometric_inscription,
    "Etched into the floor around the plinth, in a language that shouldn't be readable \
but somehow is: 'The Astral Cat stood here before time was counted. \
Return it and the House remembers.'").
note(atrium, research_scrawl,
    "A torn page from a researcher's notebook, wedged under the plinth: \
'The resonance patterns converge at this point. Whatever belonged here \
has been moved to the upper level for safekeeping. Bad idea. \
The room has been wrong ever since. —R.H.'").

note(resonance_lab, resonance_log,
    "Research log, partially destroyed: 'The resonance pattern coalesces around \
the object. It has begun to take the form of a weapon — a response, perhaps, \
to the paranatural energies saturating this building. Handle with extreme caution. \
Three bursts of fire were observed in testing. Do not exceed. —Dr. Darling'").
note(resonance_lab, warning_placard,
    "A laminated placard, one corner melted: 'CAUTION: OBJECT OF POWER STUDY IN \
PROGRESS. Do not interact with the resonance mass without Director clearance. \
Energy discharge may occur without warning.'").
note(resonance_lab, scrawled_note,
    "Words scratched into the wall beside the table: \
'It wants to be used. I can feel it pulling. But every time it fires, it takes \
something with it — like it is eating the air. Three shots and the lights go out. —R.H.'").

note(sub_lab, breach_memo,
    "A crumpled internal memo, nearly illegible: 'Wall failure in auxiliary lab — \
cause undetermined. Structural survey on hold pending paranatural clearance. \
DO NOT enter sub-lab until survey complete. —Facilities'").
note(sub_lab, shelf_tag,
    "A label on the shelf above the capacitor, printed in Bureau font: \
'RESONANCE CAPACITOR — CHARGE AMPLIFICATION UNIT. \
For use in weapon systems requiring extended discharge cycles. \
Handle with care. Do not exceed rated capacity.'").

note(containment_hall, breach_report,
    "A pinned incident report, water-damaged: 'CELL BLOCK C — STATUS: COMPROMISED. \
All units breached. Cause unknown. DO NOT attempt manual recontainment. \
Wait for specialist team. — NOTE: Specialist team has not arrived. \
This notice has been here for eleven days.'").

note(cell_annex, intake_log,
    "The intake log for cell block C, open to the last completed entry: \
'SUBJECT: HISS WARDEN — CELL: SOLITARY EAST. \
CLASSIFICATION: ENTITY, TYPE 4. CONTAINMENT PROTOCOL: MAXIMUM. \
NOTE: Standard containment is insufficient. Paranatural dampeners installed. \
NOTE 2: Dampeners are insufficient. Director has been informed. \
NOTE 3: Director says keep it there. It hasn't tried to leave. \
We are choosing to read that as good news.' \
The entry after it was started and then torn out.").
note(cell_annex, transfer_memo,
    "An internal transfer memo still in its envelope, opened and re-folded: \
'RE: ENTITY IN SOLITARY EAST. \
Request to transfer subject to a deeper containment level has been DENIED. \
Rationale: the building will not permit transfer. \
The entity appears to have formed a locational attachment to Solitary East. \
We have decided it is preferable to have it stationary and monitored \
than mobile and uncontained. \
Proceed with enhanced monitoring. — Director'").
note(cell_annex, cell_manifest,
    "A manifest of all occupied cells, tacked above the booking counter. \
Most entries are standard: names, Bureau case numbers, detainment reasons. \
Near the bottom, in a different ink and a different hand from all the others: \
'SOLITARY EAST — DO NOT INTERACT. DO NOT MAKE EYE CONTACT. \
DO NOT ENTER UNLESS YOU HAVE ALREADY ACCEPTED THAT YOU MAY NOT LEAVE. \
— Warden (retired)'").

note(watch_post, monitor_log,
    "A shift log beside the monitor bank, entries going back months: \
'0600: Subject stationary. 1200: Subject stationary. 1800: Subject stationary.' \
Every entry, every shift, every day. \
Then a gap of three days with nothing written. \
Then one final entry in shaking handwriting: \
'0600: Subject is no longer facing the wall.'").
note(watch_post, psych_evaluation,
    "A Bureau psychological evaluation form, partially completed for a guard named Reyes: \
'Q: Do you feel safe in your current posting? A: No. \
Q: Do you understand the purpose of your watch duties? A: I watch the thing in solitary. \
Q: Has the subject ever communicated with you directly? A: Not in words. \
Q: Please elaborate. A: It knows I'm watching. I know it knows. \
We have been having this conversation through reinforced glass for four months. \
I am requesting reassignment.' \
STATUS stamp at the bottom: DENIED.").
note(watch_post, routing_notice,
    "A handwritten note taped directly to the solitary monitor screen: \
'If you are reading this and you have a weapon, \
you are the first person in two months who might be able to do something about that. \
Go east from the hall. You'll find it. \
It will find you first but that's okay. \
It hasn\'t killed anyone yet — it\'s been waiting for something. \
I think it\'s been waiting for you. — Last shift supervisor'").

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

note(anteroom, appointment_log,
    "A leather-bound appointment diary, open on the last used page: \
'0900 — Darling (Project Threshold debrief). \
1100 — Security briefing re: upper levels. \
1400 — REDACTED.' \
The 1400 entry has been crossed out, then crossed out again, then torn half away.").
note(anteroom, commendation,
    "The framed commendation reads: 'Awarded to the Director for exceptional service \
in the containment and study of paranatural phenomena. \
The Bureau thanks you for your sacrifice.' \
Below, in the Director's handwriting: 'They knew. They always knew.'").
note(anteroom, photo_caption,
    "The photograph on the wall has a caption typed on a strip of card \
and taped below the frame: 'THRESHOLD TEAM — YEAR THREE.' \
Five people. All standing. None with faces. \
You look closer. The faces aren't missing. They're just turned away. \
All five of them, turned to face something just outside the frame.").

note(ops_room, tactical_annotation,
    "One annotation on the wall map, circled in red three times: \
'RESONANCE CONVERGENCE POINT — DO NOT TREAT AS FIXED.' \
Below it, in increasingly hurried handwriting: \
'It moves. —Day 1.' \
'It's moving faster. —Day 4.' \
'It found the weapon. —Day 7.' \
Day 8 onward is blank.").
note(ops_room, radio_log,
    "A printed radio transmission log, the last entry time-stamped at 03:14: \
'All units report Hiss incursion, floors 2 through 7. Director unresponsive. \
Containment protocol abandoned. All personnel advised to — ' \
The log ends mid-sentence. The printer is still warm.").
note(ops_room, field_report,
    "A handwritten field report, unsigned: \
'The Service Weapon does not respond to standard issue personnel. \
Attempts to retrieve have resulted in two injuries and one disappearance. \
Conclusion: the weapon is choosing. Recommend we stop sending people \
until it picks one. —Unknown'").

note(lab77, experiment_log,
    "Lab journal entry: 'The specimens respond to the resonance. Containment fields holding. —Dr. Darling'").
note(lab77, warning_sign,
    "A faded warning sign: 'DANGER: Dimensional Anomaly Active. Personnel must maintain safety protocols.'").

note(lab77_locked, door_notice,
    "The official placard beside the sealed door reads: \
'LAB 77 — RESTRICTED ACCESS — DIRECTOR CLEARANCE REQUIRED. \
Unauthorised entry will result in immediate termination of employment.' \
Below it, in biro: 'Also possibly just termination. — T'").

note(archive_bay, requisition,
    "A Bureau requisition form, unfiled: \
'Request for additional containment units, Lab 77 annex. \
Reason: current capacity exceeded. Estimated wait: 6 weeks. \
Note: we may not have 6 weeks. —Dr. Darling'").

note(secret_chamber, research_log,
    "Faded research log: 'Subject exhibits anomalous properties. Further containment required. —Dr. Darling'").
note(secret_chamber, equipment_note,
    "Scrawled note: 'The Bureau's secrets buried deep. Some doors should stay locked.'").
note(secret_chamber, final_note,
    "A hastily written note: 'If you're reading this, then the House has let you in. \
Trust nothing. Find him and get out.'").

note(demolition_room, important,
    "*** IMPORTANT *** Scrawled in large, frantic letters across a torn Bureau memo: \
'DO NOT ENTER THE ROOM TO THE NORTH. I REPEAT — DO NOT ENTER. \
Three agents went in. None came back. Whatever is in there is not containable. \
It is not survivable. Turn around. GO SOUTH. —Last surviving member of Retrieval Team 7'").

note(blast_corridor, structural_report,
    "A laminated structural survey, pinned to a buckled wall: \
'WING C — NORTH ANNEX: UNSAFE FOR OCCUPANCY. \
Load-bearing walls compromised. Ceiling integrity: critical. \
Cause of damage: designation UNKNOWN. \
Recommendation: full evacuation and controlled demolition.' \
Handwritten below: 'No one left to do the demolition. —Eng. K'").
note(blast_corridor, scorch_markings,
    "In the scorch marks on the floor, partially obscured by debris: \
a pattern. Concentric circles with a central point. \
It wasn't made by the blast. The blast happened around it. \
Something was standing here when the walls came in.").
note(blast_corridor, survivor_note,
    "Wedged behind a collapsed shelf unit, a handwritten note on Bureau stationery: \
'Whoever finds this: the shield didn't cause this. \
The shield STOPPED this. Whatever came through from the north, \
the shield held it here. That's why the room looks like this. \
That's why the shield is still there. —The last one out'").

note(evidence_vault, open_canister,
    "The open canister on the workbench is labelled: 'CASE 88-DELTA — OBJECT CLASS: RESONANT.' \
The half-finished report reads: 'Object continues to exhibit autonomous behaviour. \
It has now arranged the other canisters in the vault in order of — '").
note(evidence_vault, case_index,
    "A printed case index for the vault. Hundreds of entries. \
You scan down the list. Near the bottom, one entry has been circled in red: \
'CASE 91-ALPHA — SUBJECT: FADEN, J. — STATUS: PENDING ARRIVAL.' \
The date on the entry is today.").
note(evidence_vault, vault_memo,
    "An internal memo taped to the blast door from the inside: \
'Evidence vault secured per protocol. All case materials intact. \
Note: Case 91-Alpha file has been updated in advance of subject arrival — \
the House insisted. We have stopped asking how it knows. —Archivist'").

note(solitary, warden_log,
    "A crumpled guard log: 'Subject 117 — Faden, D. — transferred to solitary east wing \
by Director's order. Warden unit assigned for permanent containment. \
DO NOT engage subject directly. DO NOT open the east cell. \
Subject is not infected. Subject is leverage.'").
note(solitary, scratched_door,
    "Scratched into the reinforced door at the far east end, from the inside: \
'Jesse. If you somehow get here. I knew you would. —D'").

note(dylans_cell, etched_wall,
    "Scratched into the concrete beside the cot, small and careful: \
'I stopped counting days. But she'll come. She always does. \
I just have to stay me until she gets here. —D'").

/* ============================================
      NOTE PREDICATES
   ============================================ */

%% list_notes(+Room)
%  Show IDs of all unread notes in Room on arrival.
list_notes(Room) :-
    findall(Id, (note(Room, Id, _), \+ read_note(Room, Id)), Unread),
    ( Unread = [] -> true
    ; atomic_list_concat(Unread, ', ', IdStr),
      writeln(""),
      highlight_text("Unread notes here:"),
      note_text(IdStr),
      highlight_text("Use 'read <name>' to examine and read one."),
      writeln("")
    ).

%% read_notes(all)
%  Read and mark all unread notes in the current room.
read_notes(all) :-
    location(jesse, Room),
    findall(Id-Text, (note(Room, Id, Text), \+ read_note(Room, Id)), Pairs),
    ( Pairs = []
    -> note_text("There's nothing to read here.")
    ;  forall(member(Id-Text, Pairs), (
           note_text(Text),
           assertz(read_note(Room, Id))
       ))
    ).

%% read_notes(+Name)
%  Read a single named note in the current room.
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

/* ============================================
      INNER THOUGHTS — inner_thought(Room, Id, Text)
      Jesse's internal monologue; triggered with
      'think <Id>' when in the matching room.
   ============================================ */

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

inner_thought(street, unarmed,
    "You're walking into a government building that doesn't officially exist, \
dealing with things that officially can't happen — and you're unarmed. \
Smart, Jesse. Real smart. \
Whatever is in there, it's not going to care that you came in peace. \
You need a weapon. Something that can handle whatever this place throws at you. \
There has to be something inside. Find it. Before it finds you first.").

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
But in here the geometry is wrong. Corridors that shouldn't fit. Rooms that open onto \
other rooms with no space between them. \
You've been in two hallways and already you've lost your sense of direction. \
The Bureau calls it the Oldest House. \
You're starting to understand why. \
It doesn't feel built. It feels grown.").

inner_thought(lobby, exploration,
    "Dylan could be anywhere in here. \
That's the reality you have to sit with. \
This building doesn't follow normal rules — rooms shift, corridors loop, \
whole wings show up where they shouldn't be. \
You're going to have to search every corridor. Every office. \
Every locked door you can find a key for. \
Leave no room unchecked. \
He's here. And you're not leaving until you find him.").

inner_thought(atrium, patterns,
    "The floor is doing something. Moving, almost — or just on the edge of moving. \
You've seen geometry like this before. In the dreams. \
There's something missing here. Something that should be here and isn't. \
The room feels incomplete. Wrong. \
Like a sentence with the last word cut out.").

inner_thought(rejuvenation_room, healing,
    "You can feel it working. That's the strange part — not that it works, \
but that you can feel it. A warmth that starts at the edges and moves inward. \
Like the building is paying attention to you specifically, \
finding the places that are wrong and making them less wrong. \
You've been in field hospitals. You've been in ERs. \
Nothing has ever felt like this. \
This feels like being wanted intact.").

inner_thought(rejuvenation_room, cost,
    "The protocol sheet said three subjects showed anomalous results after ninety minutes. \
You don't ask what anomalous means because you think you already know. \
The building heals you because it needs you functional. \
That's a transaction, not a gift. \
You take the supplies anyway. \
You can think about what you owe later.").

inner_thought(secret_chamber, dylan,
    "There he is. Dylan. \
He looks smaller than you remember. Older. \
Whatever happened to him in here, he's still breathing. \
That's enough. That has to be enough. \
You just have to get him out.").

inner_thought(janitor_hall, ahti,
    "The janitor. Ahti. \
He shouldn't know anything useful — and yet he clearly does. \
The way he talks, the way he watches you move through this building. \
You've met people like him before. People who've been somewhere dangerous long enough \
that the danger stopped noticing them. \
Whatever Ahti's seen in here, it didn't touch him. \
You're not sure if that makes him the safest person in the building \
or the most dangerous.").

inner_thought(utility_bay, drenchtov,
    "His name badge says DRENCHTOV, B. — Bureau Administration, Grade 3. \
He is eating a sandwich. \
The building is overrun, something is wrong with the walls, \
people are dead, and he is eating a sandwich and filling in a form. \
You've seen this before too: a certain kind of person who converts terror \
into paperwork and paperwork into calm. \
He's not okay. But he has a system. \
Right now, you almost envy him the system.").

inner_thought(directors_office, director,
    "He's still here. The Director. \
Something moved him to end it in his own office, in his own chair, \
gun in hand — and whatever it was, he left the weapon behind. \
You don't know his name. You don't know what he saw. \
But you know this building chose him once, \
and it's pointing at you now. \
You pick up the gun. It feels right. \
That's the part that scares you.").

inner_thought(anteroom, waiting,
    "Someone sat in this room not long ago and waited to go in. \
Maybe for good news. Maybe for orders. \
Maybe they already knew what they were going to find and sat here anyway, \
because the waiting was better than the knowing. \
You understand that. You sat in a lot of waiting rooms before you got here. \
This one just has better furniture.").

inner_thought(ops_room, map,
    "The annotations stop on day seven. \
Whatever the Director saw on day seven was enough. \
You look at the map. The room marked RESONANCE CONVERGENCE POINT \
is the atrium. You've been there. You stood in it. \
You didn't feel like a convergence point. \
You felt like someone standing in a very large room \
not entirely sure what was happening. \
Maybe that's the same thing.").

inner_thought(upper_hall, deeper,
    "You're further in than you meant to go. \
The lobby felt like a threshold — something you could still step back from. \
This doesn't. \
The corridor hums at a frequency you feel in your back teeth. \
You think about Dylan. You think about how he would have walked in here \
without hesitation, without thinking it through. \
You think maybe that's the difference between you. \
You think it too, anyway. And here you are.").

inner_thought(containment_hall, cells,
    "The doors are all hanging open. \
Whatever was in these cells didn't wait to be let out. \
You try not to think about what was strong enough to do that \
and what might still be in here doing it. \
Keep moving. Don't look in the cells. \
You already broke the second rule.").

inner_thought(cell_annex, intake,
    "Solitary East. The intake log gives it a cell number and a classification \
like it's just another detainee. \
Type 4 Entity. Maximum containment. Three escalating notes in the same file \
and then a page torn out. \
Whatever they put in that room, the paperwork stopped being adequate pretty quickly. \
You look east toward the hall. \
Something is at the end of it. \
You already knew that.").

inner_thought(watch_post, watching,
    "Someone sat in this chair every day for months and watched a screen \
showing something that didn't move, in a room that shouldn't exist on most floor plans. \
And then one day it stopped facing the wall. \
And then the log stops. \
The feed is still running. \
You can see the corridor in solitary from here, the same fixed angle. \
You don't look at what's at the end of it. \
You already know what's there. \
You're going to have to go east eventually.").

inner_thought(solitary, warden,
    "Something is wrong with the air in here. \
Heavy. Charged. Like standing near a transformer. \
Whatever is at the end of this block, it's been here a long time. \
Long enough that the building built itself around it. \
You tighten your grip on the Service Weapon. \
It hums back at you, just slightly. \
Okay. That's either reassuring or terrifying. \
Probably both.").

inner_thought(resonance_lab, form,
    "It looks like a weapon the way a thunderstorm looks like weather. \
Technically accurate. Catastrophically understated. \
You can feel it pulling at the edges of your attention — \
not threatening, exactly. More like a question being asked \
in a frequency your brain isn't built to answer. \
You're going to pick it up anyway. \
You already know that. The room already knows that.").

inner_thought(food_vendor, locked_box,
    "There's a locked box next to the food cart. The vendor hasn't mentioned it. \
Maybe he doesn't know what's in it. Maybe he put it there and forgot. \
The code has to be somewhere in this building — the Bureau documented everything. \
Someone wrote it down. You just have to find the right piece of paper.").

inner_thought(north_alley, outside,
    "You're outside. Actually outside. \
The sky is still there — the same sky, the same light, the same air. \
None of that changed. \
The building behind you is taller from back here somehow, \
as if the alley is designed to make you feel it. \
You look up and don't bother counting the floors. \
Something in there is waiting for you to come back in. \
You already know you're going to.").

inner_thought(south_lot, cars,
    "All those cars. All those people who drove to work this morning \
and parked in their usual spot and grabbed their badge from the passenger seat \
and walked in through the front door. \
Ordinary morning. Coffee. The permit on the car that says Level 4 Clearance \
and a name you recognise. \
You think about what it means to park your car and never come back for it. \
You think about it for longer than you mean to.").

inner_thought(west_road, leaving,
    "You could just walk. Nothing is stopping you. \
Dylan isn't waiting at the end of every road in the world — just this one. \
You look west. Somewhere out there is a normal city doing normal things. \
You turn around. \
You've been turning around all your life. \
Just not usually this deliberately.").

inner_thought(toilets, ordinary,
    "Running water. Lights that work. The smell of industrial cleaner. \
There is something almost funny about the whole thing — \
the rest of the building is falling apart and the facilities are still clean. \
You check your weapon. You breathe. \
One minute of being a person in a bathroom. \
Then back to work.").

inner_thought(pipe_room, hidden,
    "Someone hid this here on purpose. \
Not dropped, not left behind — hidden. \
Wrapped up and pushed behind a pipe inside a wall \
that you can only get through if you're carrying a paranatural breach object. \
Whoever put this here knew it would stay hidden from almost everyone. \
They were either very careful or very scared. \
You suspect both.").

inner_thought(sub_lab, capacitor,
    "An extended discharge unit — Bureau designation, shelf tag, everything labelled. \
They were ready for this. Or ready for something like this. \
You wonder if there's a difference. \
You slide it into your pocket. \
It doesn't hum. That's either a good sign or it just hasn't warmed up yet.").

inner_thought(dylans_cell, finally,
    "You've been rehearsing this in your head since the front door. \
You thought you'd be angry. You thought maybe you'd arrive too late. \
You didn't plan for him to just be Dylan — \
exhausted, in a cell, watching the door like he knew exactly when it would open. \
You didn't plan for that to be the hard part.").

inner_thought(security_post, static,
    "Every monitor is static. You stand in front of the bank of screens \
and look for a pattern in the noise. There isn't one. \
Or there is and it's running at a frequency you can't read. \
Someone sat here every shift watching for exactly this. \
The static was probably already there when they left. \
They just didn't know what it meant yet.").

inner_thought(records_room, files,
    "This is the paper trail of something that shouldn't exist. \
Incidents, containment protocols, personnel evaluations — all filed, indexed, \
cross-referenced. The Bureau didn't just study the paranatural. They administered it. \
It had a budget. Quarterly reviews. Probably HR complaints. \
You'd laugh, but the H files are apparently walking.").

inner_thought(lab77, darling,
    "Darling's name is on everything in here. \
The experiment logs, the safety protocols, the containment assessments. \
Bureau's lead researcher. Face of institutional optimism \
in the middle of dimensional collapse. \
You wonder if he's still somewhere in the building. \
You have a feeling that wondering that is the bad kind of sign.").

inner_thought(demolition_room, shield,
    "It's hovering. A few inches off the pedestal, rotating just slightly. \
An Object of Power — same category as the Service Weapon. \
You can feel it the same way: present, aware, waiting. \
The demolition didn't touch it. Whatever took out the walls \
hit everything else and left the shield exactly where it was. \
It chose to stay. You walk toward it.").

inner_thought(blast_corridor, blast,
    "The blast came from inside. \
You can tell from the way the walls folded — \
pressure expanding outward from a central point. \
Whatever happened in the main chamber, the corridor caught the overflow. \
And yet something was standing here in the middle of it \
and left a pattern in the floor instead of a body. \
You file that under things to think about later.").

inner_thought(evidence_vault, case_file,
    "Your name is in a file here. \
Not Dylan's. Yours. \
Date: today. Status: pending arrival. \
They were expecting you before you knew you were coming. \
You think about what that means. \
You think about whether the Bureau found you or you found the Bureau. \
You decide that question might not have an answer you want.").

inner_thought(archive_bay, records,
    "The Bureau kept records of everything. \
Every anomaly, every incident, every person who walked in and didn't come out the same. \
You had the idea that if you read enough files you could get ahead of it. \
You open a crate. It hums faintly. \
You close it again.").

%% list_thoughts(+Room)
%  Show available thought IDs for the current room.
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

%% think_thought(+Name)
%  Display a named inner thought if available in the current room.
think_thought(Name) :-
    location(jesse, Room),
    ( inner_thought(Room, Name, Text)
    -> normal_text(Text)
    ;  normal_text("You can't focus on that right now.")
    ).

/* ============================================
      PLACE ITEM PUZZLE ACTIONS
      Items that must be placed in specific rooms
      to trigger puzzle effects.
   ============================================ */

%% place_item(cat_statue)
%  Place the cat statue on the atrium plinth to spawn upgrade items.
place_item(cat_statue) :-
    location(jesse, atrium), has(jesse, cat_statue), \+ cat_statue_placed, !,
    retract(has(jesse, cat_statue)),
    assertz(cat_statue_placed),
    highlight_text("You set the cat statue on the stone plinth."),
    normal_text("It fits perfectly. The geometric patterns on the floor pulse once, faintly, then settle."),
    normal_text("A deep resonant tone fills the chamber. Two objects materialise from the light."),
    assertz(object(health_upgrade, atrium)),
    assertz(object(charge_upgrade, atrium)),
    tip_text("New items have appeared! Use 'take health_upgrade' and 'take charge_upgrade'.").

place_item(cat_statue) :-
    cat_statue_placed, !,
    normal_text("The cat statue is already placed on the plinth.").

place_item(cat_statue) :-
    \+ location(jesse, atrium), has(jesse, cat_statue), !,
    normal_text("That doesn't seem like the right place for it. The statue feels drawn elsewhere.").

place_item(cat_statue) :-
    normal_text("You don't have the cat statue.").

%% place_item(flower)
%  Lay the flower on west_road to spawn a health kit.
place_item(flower) :-
    location(jesse, west_road), has(jesse, flower), !,
    retract(has(jesse, flower)),
    assertz(object(health_kit, west_road)),
    highlight_text("You lay the wildflower against the old brick wall."),
    normal_text("It looks right here. Like it belonged all along."),
    normal_text("Something shifts in the air — a faint warmth, almost grateful."),
    tip_text("A health kit has appeared! Use 'take health_kit' to pick it up.").

place_item(flower) :-
    \+ location(jesse, west_road), has(jesse, flower), !,
    normal_text("You hold the flower carefully. It feels like it belongs somewhere quieter than this.").

place_item(flower) :-
    normal_text("You don't have a flower.").

%% place_item(+Item) — fallback for unplaceable items
place_item(Item) :-
    format(atom(Msg), "You can't place the ~w here.", [Item]),
    normal_text(Msg).

/* ============================================
      DIALOGUE
      NPC conversation handlers.
      Each talk_to/1 clause guards on location.
   ============================================ */

talk_to(ahti) :-
    location(jesse, janitor_hall), !,
    ( has(jesse, keys)
    -> speak(ahti, "'Good. Keys open many doors,' Ahti says with a grin.")
    ;  speak(ahti, "'Lost? Keys are in the lobby,' Ahti says, pointing back.")
    ).

talk_to(okoro) :-
    location(jesse, lab77), !,
    normal_text("A researcher in a white coat looks up from a terminal, visibly relieved to see another person."),
    speak(okoro, "'Oh thank god. I thought I was the last one in this wing.'"),
    normal_text("He gestures at the bench where the smash object sits."),
    speak(okoro, "'Okoro. Materials Research. I've been here since the incident started \
and I haven't left because — well, look at it.'"),
    normal_text("He means the smash object. It's sitting perfectly still but seems somehow present."),
    speak(okoro, "'It's a kinetic resonance object. Class: Breach. \
We've been studying it for six months and the short version is: \
it wants to go through things. Walls, specifically. \
Sealed surfaces. Blocked passages.'"),
    speak(okoro, "'You don't activate it. You don't aim it. \
You just carry it. \
Once you have it on you, certain sealed areas become navigable \
— the object and the wall come to some kind of arrangement \
and the path opens up.'"),
    normal_text("He pulls up a schematic on the terminal."),
    speak(okoro, "'From here, there's a chamber to the south that's been sealed since the seventies. \
The object will get you through. \
And there's a sub-level off the resonance lab on this floor — \
same principle. Carry it, the way opens.'"),
    speak(okoro, "'Take it. Carefully. \
Don't put it down near anything structural you want to keep standing.'"),
    normal_text("He sits back down at his terminal with the air of someone \
who has done everything they can and is now waiting to see what happens.").

talk_to(hartwell) :-
    location(jesse, demolition_room), !,
    normal_text("She's crouched near the pedestal, making notes on a clipboard. \
She doesn't look up immediately."),
    speak(hartwell, "'Don't touch it yet.'"),
    normal_text("She stands, tucks the clipboard under her arm, and faces you."),
    speak(hartwell, "'Hartwell. Parapsychics, Object Research. I've been studying this thing \
since it arrived in this room, which was — '"),
    normal_text("She checks the time."),
    speak(hartwell, "'— not long, in the grand scheme of things. Long enough."),
    speak(hartwell, "It's a resonance object. Object of Power. Class: Shielding. \
What it does is absorb. One significant kinetic or paranatural impact — one hit — \
then the barrier dissipates. Has to be reactivated manually each time.'"),
    normal_text("You look at the shield hovering above the pedestal."),
    speak(hartwell, "'Take it. It won't hurt you — it's already decided it wants a new host. \
I've been watching it orient toward the door every time someone walks past. \
That's you, by the way. It's been orienting toward you.'"),
    speak(hartwell, "'When you need it, use the shield command. \
You'll know when. The barrier goes up, takes the next hit, then it's gone. \
Only good for one blow at a time, so don't waste it. \
Use it when something is about to hurt you badly.'"),
    normal_text("She turns back to her clipboard."),
    speak(hartwell, "'I'd come with you but I have seventeen pages of field notes to finish \
and the object isn't going to document itself. Good luck. \
Try not to die."),
    speak(hartwell, "Also — north of here is very bad. You probably already know that.'").

talk_to(drenchtov) :-
    location(jesse, utility_bay), !,
    speak(drenchtov, "'Oh. Hello.' He sets down his sandwich."),
    normal_text("He looks at the Service Weapon. He looks at you. He looks back at his form."),
    speak(drenchtov, "'Right. Are you by any chance the new Director?'"),
    normal_text("You are not the new Director."),
    speak(drenchtov, "'No, of course not. Too early.' He makes a small note."),
    speak(drenchtov, "'I've been trying to reach someone in authority for — '"),
    normal_text("He checks his watch."),
    speak(drenchtov, "'— some time now. The Director's office is north, past the lobby, up through the building. \
Senior staff would normally handle a situation like this but as far as I can tell \
senior staff are either dead or making things considerably worse, so.'"),
    normal_text("He picks up his sandwich again."),
    speak(drenchtov, "'I'd try north of the lobby. That's where the Director works. Worked. \
I'm going to stay here and finish this form. \
Someone has to keep the paperwork current.'"),
    normal_text("He seems sincere. You believe him. \
You also believe he is going to be fine, in the way that very organised people \
are sometimes inexplicably fine.").

talk_to(vendor) :-
    location(jesse, food_vendor), !,
    speak(vendor, "'Get your hyperreal hot‑dogs! Two for one if you say the word \"bureau\"!'"),
    normal_text("He laughs maniacally and jots something down on a napkin.").

talk_to(dylan) :-
    location(jesse, dylans_cell), !,
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

%% show_credits — end‑game credits screen, then lock input loop.
show_credits :-
    map_text(""),
    map_text("╔══════════════════════════════════════════╗"),
    map_text("║               ~ FIN ~                    ║"),
    map_text("╠══════════════════════════════════════════╣"),
    map_text("║                                          ║"),
    map_text("║   CONTROL — TEXT ADVENTURE               ║"),
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

/* ============================================
      COMBAT
      Each named enemy has its own pair of
      predicates:

        combat(jesse, <enemy>)
          Called by dispatch(attack) or
          dispatch(attack(<enemy>)).
          Validates weapon ownership and enemy
          liveness, prints damage, then calls
          fire_weapon/2 to deduct charge.
          On success, immediately invokes the
          matching enemy_turn_* predicate.

        enemy_turn_* / enemy_turn
          Checks if the enemy just died.
            • Dead  → print kill banner, remove
                      from location, recharge weapon,
                      apply any death rewards
                      (e.g. dylans_cell_key from boss).
            • Alive → print retaliation message
                      and call take_enemy_hit/1.

      Enemy damage values:
        hiss_guard / hiss_guard_b — deals 25 per hit;
                                    30 HP pool
        hiss_brute                — deals 30 per hit;
                                    50 HP pool
        hiss_boss (Warden)        — deals 35 per hit;
                                    100 HP pool;
                                    player deals 15/shot
        hiss_infection_N          — deals 20 per hit;
                                    30 HP pool

      Shared helpers:
        fire_weapon(+Enemy, +Dmg)
          — check charge > 0, deal Dmg to Enemy,
            decrement charge by 1.
        take_enemy_hit(+Dmg)
          — if shield_active: absorb and clear flag;
            else subtract Dmg from Jesse's HP and
            call check_death/0.
        check_death/0
          — assert game_over and print death screen
            if Jesse's HP ≤ 0.
        recharge (inline after kill)
          — restore weapon_charge to max_weapon_charge.
   ============================================ */

/* --- Shared helpers --- */

%% take_enemy_hit(+Dmg)
%  Subtract Dmg from Jesse's health, or absorb with shield if active.
%  After applying damage, prints both HP and charge as a HUD update,
%  then calls check_death/0.
take_enemy_hit(Dmg) :-
    ( shield_active
    -> retract(shield_active),
       highlight_text("The shield absorbs the blow! You take no damage."),
       highlight_text("The shield's barrier dissipates.")
    ;  health(jesse, JHP),
       NewJHP is JHP - Dmg,
       retract(health(jesse, JHP)),
       assertz(health(jesse, NewJHP)),
       max_health(jesse, MaxHP),
       format(atom(HMsg), "Your Health: ~w/~w", [NewJHP, MaxHP]),
       highlight_text(HMsg),
       weapon_charge(jesse, C),
       max_weapon_charge(jesse, MC),
       format(atom(CMsg), "Weapon Charge: ~w/~w", [C, MC]),
       highlight_text(CMsg),
       check_death
    ).

%% check_death
%  Assert game_over and print death screen if Jesse's HP ≤ 0.
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

%% weapon_dmg(+Base, -Actual, -Crit)
%  Returns actual damage and whether it was a critical hit.
%  1-in-3 chance of crit: triples the (possibly weapon-form-boosted) damage.
%  weapon_form_active first multiplies by 3, then crit multiplies by 3 again.
weapon_dmg(Base, Actual, Crit) :-
    ( weapon_form_active -> Boosted is Base * 3 ; Boosted = Base ),
    random_between(1, 3, Roll),
    ( Roll =:= 1
    -> Actual is Boosted * 3, Crit = true
    ;  Actual = Boosted,      Crit = false
    ).

%% fire_weapon(+Enemy, +BaseDmg)
%  Core attack logic shared by all combat/2 clauses.
%  If weapon_form_active: damage is 3× BaseDmg and costs 3 charges.
%  Otherwise: damage is BaseDmg and costs 1 charge.
%  1-in-3 chance of critical hit: triples the final damage.
%  Fails (with message) if charge is insufficient for the current cost.
%  On success: subtracts actual Dmg from Enemy's health fact and
%  decrements Jesse's weapon_charge by the cost.
fire_weapon(Enemy, FinalDmg, Cost) :-
    weapon_charge(jesse, Charge),
    ( Charge < Cost
    -> highlight_text("Your weapon lacks the charge for that! Use 'skip' to recharge."),
       fail
    ;  health(Enemy, HP),
       NewHP is HP - FinalDmg,
       retractall(health(Enemy, _)),
       assertz(health(Enemy, NewHP)),
       NewCharge is Charge - Cost,
       retractall(weapon_charge(jesse, _)),
       assertz(weapon_charge(jesse, NewCharge))
    ).

%% hiss_attack_line(+DisplayName, -Line)
%  Picks a random attack message from the pool, formatting
%  DisplayName into the chosen template.
hiss_attack_line(Name, Line) :-
    Templates = [
        "~w lashes out!",
        "~w lunges at you!",
        "~w slams into you!",
        "~w tears at your mind!",
        "~w strikes with violent force!",
        "~w surges forward!",
        "~w howls and attacks!",
        "~w bears down on you!",
        "~w closes in fast!"
    ],
    random_member(Template, Templates),
    format(string(Line), Template, [Name]).

/* --- Hiss Guard (spawned in upper_hall when service_weapon is taken) ---
   HP: 30  |  Player damage: 10/shot  |  Retaliates: 25 damage
   Three clauses (ordered, each cut):
     1. No weapon yet  → explain and fail gracefully.
     2. Weapon + alive → fire, then enemy_turn.
     3. Already dead   → report and stop.                          --- */

combat(jesse, hiss_spawn) :-
    \+ has(jesse, service_weapon), !,
    normal_text("You reach for a weapon... but you don't have the Service Weapon yet.").

combat(jesse, hiss_spawn) :-
    location(jesse, Room), location(hiss_spawn, Room),
    has(jesse, service_weapon), health(hiss_spawn, HP), HP > 0, !,
    ( weapon_form_active -> Cost = 3 ; Cost = 1 ),
    weapon_dmg(10, ActDmg, Crit),
    ( Crit = true -> format(string(CM), "Critical hit! (~w damage)", [ActDmg]), highlight_text(CM) ; true ),
    NewHP is HP - ActDmg,
    format(atom(Msg), "Hiss Spawn health: ~w -> ~w", [HP, NewHP]),
    normal_text("You fire!"),
    note_text(Msg),
    ( fire_weapon(hiss_spawn, ActDmg, Cost)
    -> enemy_turn_spawn
    ;  true
    ).

combat(jesse, hiss_spawn) :- !,
    normal_text("The Hiss Spawn is already dead.").

enemy_turn_spawn :-
    ( health(hiss_spawn, HP), HP =< 0
    -> highlight_text("═══════════════════════════════════"),
       highlight_text("The Hiss Spawn dissolves into static."),
       highlight_text("═══════════════════════════════════"),
       ( location(hiss_spawn, R) -> retract(location(hiss_spawn, R)) ; true ),
       ( max_weapon_charge(jesse, MC)
       -> retractall(weapon_charge(jesse, _)),
          assertz(weapon_charge(jesse, MC)),
          format(atom(RMsg), "Service Weapon recharged to ~w/~w.", [MC, MC]),
          highlight_text(RMsg)
       ;  true
       )
    ;  hiss_attack_line('Hiss Spawn', AL), normal_text(AL),
       take_enemy_hit(8)
    ), !.
enemy_turn_spawn.

combat(jesse, hiss_guard) :-
    \+ has(jesse, service_weapon), !,
    normal_text("You reach for a weapon... but you don't have the Service Weapon yet.").

combat(jesse, hiss_guard) :-
    has(jesse, service_weapon), health(hiss_guard, HP), HP > 0, !,
    ( weapon_form_active -> Cost = 3 ; Cost = 1 ),
    weapon_dmg(10, ActDmg, Crit),
    ( Crit = true -> format(string(CM), "Critical hit! (~w damage)", [ActDmg]), highlight_text(CM) ; true ),
    NewHP is HP - ActDmg,
    format(atom(Msg), "Hiss Guard health: ~w -> ~w", [HP, NewHP]),
    normal_text("You fire!"),
    note_text(Msg),
    ( fire_weapon(hiss_guard, ActDmg, Cost)
    -> enemy_turn
    ;  true
    ).

combat(jesse, hiss_guard) :- !,
    normal_text("The Hiss Guard is already dead.").

enemy_turn :-
    ( health(hiss_guard, HP), HP =< 0
    -> highlight_text("═══════════════════════════════════"),
       highlight_text("The Hiss Guard collapses into silence."),
       highlight_text("═══════════════════════════════════"),
       ( location(hiss_guard, R) -> retract(location(hiss_guard, R)) ; true ),
       ( max_weapon_charge(jesse, MC)
       -> retractall(weapon_charge(jesse, _)),
          assertz(weapon_charge(jesse, MC)),
          format(atom(RMsg), "Service Weapon recharged to ~w/~w.", [MC, MC]),
          highlight_text(RMsg)
       ;  true
       ),
       ( health_kit_tip_shown -> true
       ; tip_text("Tip: look for health_kit items in rooms to restore health."),
         assertz(health_kit_tip_shown)
       )
    ;  hiss_attack_line('Hiss Guard', AL), normal_text(AL),
       take_enemy_hit(25)
    ), !.
enemy_turn.

/* --- Hiss Guard B (starts in containment_hall) ---
   HP: 30  |  Player damage: 10/shot  |  Retaliates: 25 damage
   Two clauses (ordered, each cut):
     1. Weapon + alive → fire, then enemy_turn_guard_b.
     2. Already dead   → report and stop.                          --- */

combat(jesse, hiss_guard_b) :-
    location(jesse, Room), location(hiss_guard_b, Room),
    has(jesse, service_weapon), health(hiss_guard_b, HP), HP > 0, !,
    ( weapon_form_active -> Cost = 3 ; Cost = 1 ),
    weapon_dmg(10, ActDmg, Crit),
    ( Crit = true -> format(string(CM), "Critical hit! (~w damage)", [ActDmg]), highlight_text(CM) ; true ),
    NewHP is HP - ActDmg,
    format(atom(Msg), "Hiss Guard health: ~w -> ~w", [HP, NewHP]),
    normal_text("You fire!"),
    note_text(Msg),
    ( fire_weapon(hiss_guard_b, ActDmg, Cost)
    -> enemy_turn_guard_b
    ;  true
    ).

combat(jesse, hiss_guard_b) :- !,
    normal_text("The Hiss Guard is already dead.").

enemy_turn_guard_b :-
    ( health(hiss_guard_b, HP), HP =< 0
    -> highlight_text("═══════════════════════════════════"),
       highlight_text("The Hiss Guard collapses into silence."),
       highlight_text("═══════════════════════════════════"),
       ( location(hiss_guard_b, R) -> retract(location(hiss_guard_b, R)) ; true ),
       ( max_weapon_charge(jesse, MC)
       -> retractall(weapon_charge(jesse, _)),
          assertz(weapon_charge(jesse, MC)),
          format(atom(RMsg), "Service Weapon recharged to ~w/~w.", [MC, MC]),
          highlight_text(RMsg)
       ;  true
       )
    ;  hiss_attack_line('Hiss Guard', AL), normal_text(AL),
       take_enemy_hit(25)
    ), !.
enemy_turn_guard_b.

/* --- Hiss Brute (starts in atrium) ---
   HP: 50  |  Player damage: 10/shot  |  Retaliates: 30 damage
   Two clauses (ordered, each cut):
     1. Weapon + alive → fire, then enemy_turn_brute.
     2. Already dead   → report and stop.                          --- */

combat(jesse, hiss_brute) :-
    location(jesse, Room), location(hiss_brute, Room),
    has(jesse, service_weapon), health(hiss_brute, HP), HP > 0, !,
    ( weapon_form_active -> Cost = 3 ; Cost = 1 ),
    weapon_dmg(10, ActDmg, Crit),
    ( Crit = true -> format(string(CM), "Critical hit! (~w damage)", [ActDmg]), highlight_text(CM) ; true ),
    NewHP is HP - ActDmg,
    format(atom(Msg), "Hiss Brute health: ~w -> ~w", [HP, NewHP]),
    normal_text("You fire!"),
    note_text(Msg),
    ( fire_weapon(hiss_brute, ActDmg, Cost)
    -> enemy_turn_brute
    ;  true
    ).

combat(jesse, hiss_brute) :- !,
    normal_text("The Hiss Brute is already dead.").

enemy_turn_brute :-
    ( health(hiss_brute, HP), HP =< 0
    -> highlight_text("═══════════════════════════════════"),
       highlight_text("The Hiss Brute crashes to the ground, silenced."),
       highlight_text("═══════════════════════════════════"),
       ( location(hiss_brute, R) -> retract(location(hiss_brute, R)) ; true ),
       ( max_weapon_charge(jesse, MC)
       -> retractall(weapon_charge(jesse, _)),
          assertz(weapon_charge(jesse, MC)),
          format(atom(RMsg), "Service Weapon recharged to ~w/~w.", [MC, MC]),
          highlight_text(RMsg)
       ;  true
       )
    ;  hiss_attack_line('Hiss Brute', AL), normal_text(AL),
       take_enemy_hit(20)
    ), !.
enemy_turn_brute.

/* --- Hiss Boss / Warden (starts in solitary) ---
   HP: 100  |  Player damage: 15/shot  |  Retaliates: 35 damage
   On death: drops dylans_cell_key and tips the player.
   Two clauses (ordered, each cut):
     1. Weapon + alive → fire, then enemy_turn_boss.
     2. Already dead   → report and stop.                          --- */

combat(jesse, hiss_boss) :-
    location(jesse, Room), location(hiss_boss, Room),
    has(jesse, service_weapon), health(hiss_boss, HP), HP > 0, !,
    ( weapon_form_active -> Cost = 3 ; Cost = 1 ),
    weapon_dmg(15, ActDmg, Crit),
    ( Crit = true -> format(string(CM), "Critical hit! (~w damage)", [ActDmg]), highlight_text(CM) ; true ),
    NewHP is HP - ActDmg,
    format(atom(Msg), "You fire at the Hiss Warden! Boss health: ~w -> ~w", [HP, NewHP]),
    normal_text(Msg),
    ( fire_weapon(hiss_boss, ActDmg, Cost)
    -> enemy_turn_boss
    ;  true
    ).

combat(jesse, hiss_boss) :- !,
    normal_text("The Hiss Warden is already defeated.").

enemy_turn_boss :-
    ( health(hiss_boss, HP), HP =< 0
    -> highlight_text("═══════════════════════════════════"),
       highlight_text("The Hiss Warden crashes to the floor. Silence fills the block."),
       highlight_text("═══════════════════════════════════"),
       ( location(hiss_boss, R) -> retract(location(hiss_boss, R)) ; true ),
       ( max_weapon_charge(jesse, MC)
       -> retractall(weapon_charge(jesse, _)),
          assertz(weapon_charge(jesse, MC)),
          format(atom(RMsg), "Service Weapon recharged to ~w/~w.", [MC, MC]),
          highlight_text(RMsg)
       ;  true
       ),
       assertz(has(jesse, dylans_cell_key)),
       highlight_text("A KEY clatters to the floor. A label reads: CELL E‑1."),
       highlight_text("You pick up Dylan's cell key."),
       tip_text("The east door is now unlocked. Use 'go east' to reach Dylan's cell.")
    ;  hiss_attack_line('Hiss Warden', AL), normal_text(AL),
       take_enemy_hit(35)
    ), !.
enemy_turn_boss.

/* --- Hiss Infection (dynamically spawned, atom hiss_infection_N) ---
   HP: 30  |  Player damage: 10/shot  |  Retaliates: 20 damage
   Entity atom is matched via atom_concat(hiss_infection_, _, Enemy).
   On death: clears hiss_infected(Room) flag and drops a health kit
   via on_hiss_defeated/1.
   Three clauses (ordered, each cut):
     1. Weapon + alive → fire, then enemy_turn_infection.
     2. Known infection atom, not alive → report.
     3. Fallback combat clause (any non-matched enemy).            --- */

combat(jesse, Enemy) :-
    atom_concat(hiss_infection_, _, Enemy),
    location(jesse, Room), location(Enemy, Room),
    has(jesse, service_weapon), health(Enemy, HP), HP > 0, !,
    ( weapon_form_active -> Cost = 3 ; Cost = 1 ),
    weapon_dmg(10, ActDmg, Crit),
    ( Crit = true -> format(string(CM), "Critical hit! (~w damage)", [ActDmg]), highlight_text(CM) ; true ),
    NewHP is HP - ActDmg,
    format(atom(Msg), "You fire at the Hiss! Enemy health: ~w -> ~w", [HP, NewHP]),
    normal_text(Msg),
    ( fire_weapon(Enemy, ActDmg, Cost)
    -> enemy_turn_infection(Enemy, Room)
    ;  true
    ).

combat(jesse, Enemy) :-
    atom_concat(hiss_infection_, _, Enemy), !,
    normal_text("That enemy is already defeated.").

enemy_turn_infection(Enemy, Room) :-
    ( health(Enemy, HP), HP =< 0
    -> highlight_text("═══════════════════════════════════"),
       highlight_text("The Hiss infection is purged!"),
       highlight_text("═══════════════════════════════════"),
       retract(location(Enemy, Room)),
       ( max_weapon_charge(jesse, MC)
       -> retractall(weapon_charge(jesse, _)),
          assertz(weapon_charge(jesse, MC)),
          format(atom(RMsg), "Service Weapon recharged to ~w/~w.", [MC, MC]),
          highlight_text(RMsg)
       ;  true
       ),
       on_hiss_defeated(Room)
    ;  hiss_attack_line('Hiss Infection', AL), normal_text(AL),
       take_enemy_hit(20)
    ), !.
enemy_turn_infection(_, _).

%% Fallback — catches attack commands with no valid target
combat(_, _) :-
    normal_text("There's nothing to attack here.").

/* ============================================
      SKIP TURN
      Recharges weapon by 1 and lets the
      highest-priority live enemy retaliate.

      Priority order (highest first):
        hiss_boss  →  hiss_brute  →  hiss_guard_b
        →  hiss_infection_N  →  hiss_guard (fallback)

      Only usable when a live enemy is present.
      If the weapon is already at max charge,
      the player is told but the enemy still
      retaliates — so use with care.
   ============================================ */

skip_turn :-
    location(jesse, Room),
    living_enemy_here(Room), !,
    weapon_charge(jesse, OldCharge),
    max_weapon_charge(jesse, MaxCharge),
    ( OldCharge >= MaxCharge
    -> highlight_text("Your Service Weapon charge is already at maximum!")
    ;  NewCharge is min(MaxCharge, OldCharge + 1),
       retract(weapon_charge(jesse, OldCharge)),
       assertz(weapon_charge(jesse, NewCharge)),
       format(atom(Msg), "Weapon recharged: ~w -> ~w/~w", [OldCharge, NewCharge, MaxCharge]),
       highlight_text(Msg)
    ),
    normal_text("You hold your ground. The enemy seizes the moment..."),
    ( location(hiss_boss,    Room), health(hiss_boss,    HP0), HP0 > 0 -> enemy_turn_boss
    ; location(hiss_brute,   Room), health(hiss_brute,   HP1), HP1 > 0 -> enemy_turn_brute
    ; location(hiss_guard_b, Room), health(hiss_guard_b, HP2), HP2 > 0 -> enemy_turn_guard_b
    ; location(hiss_spawn,   Room), health(hiss_spawn,   HPS), HPS > 0 -> enemy_turn_spawn
    ; location(E, Room), atom_concat(hiss_infection_, _, E),
      health(E, EHP), EHP > 0                                           -> enemy_turn_infection(E, Room)
    ; enemy_turn   % hiss_guard fallback
    ).

skip_turn :-
    normal_text("You can only skip your turn during combat.").

/* ============================================
      HISS INFECTION SYSTEM
      After the Service Weapon is obtained,
      rooms have a 20% chance to become infected
      each time Jesse enters them.
      Defeated infections drop a health kit.
   ============================================ */

%% infectable_room(+Room)
%  Rooms eligible for random Hiss infection.
infectable_room(lobby).
infectable_room(atrium).
infectable_room(rejuvenation_room).
infectable_room(resonance_lab).
infectable_room(containment_hall).
infectable_room(cell_annex).
infectable_room(watch_post).
infectable_room(janitor_hall).
infectable_room(utility_bay).
infectable_room(upper_hall).
infectable_room(directors_office).
infectable_room(anteroom).
infectable_room(ops_room).
infectable_room(security_post).
infectable_room(records_room).
infectable_room(blast_corridor).
infectable_room(evidence_vault).
infectable_room(lab77).
infectable_room(archive_bay).
infectable_room(toilets).
infectable_room(pipe_room).
infectable_room(food_vendor).
infectable_room(secret_chamber).
infectable_room(death_room).

%% room_enemy_free(+Room)
%  True if no non-NPC entities are currently in Room.
room_enemy_free(Room) :-
    \+ (location(E, Room), E \= jesse, E \= ahti, E \= vendor).

%% next_hiss_id(-Id)
%  Generate a unique atom for a new infection entity (e.g. hiss_infection_3).
next_hiss_id(Id) :-
    aggregate_all(count, hiss_infected(_), N),
    atomic_list_concat([hiss_infection_, N], Id).

%% infect_room(+Room)
%  Spawn a new Hiss infection entity in Room and alert the player.
infect_room(Room) :-
    \+ hiss_infected(Room),
    assertz(hiss_infected(Room)),
    next_hiss_id(Id),
    assertz(location(Id, Room)),
    assertz(health(Id, 30)),
    room_name(Room, RoomName),
    ( location(jesse, Room)
    -> atomic_list_concat(['!! HISS INFECTION AT ', RoomName, ' — AN ENEMY HAS APPEARED HERE !!'], Alert)
    ;  atomic_list_concat(['[ALERT] Hiss infection detected at ', RoomName, '.'], Alert)
    ),
    note_text(Alert).

%% maybe_true(+Prob)
%  Succeeds with probability Prob (0.0–1.0).
maybe_true(Prob) :-
    random(R), R < Prob.

%% maybe_infect(+Room)
%  20% chance to infect an eligible, enemy-free room.
maybe_infect(Room) :-
    ( \+ hiss_infected(Room), room_enemy_free(Room), maybe_true(0.2)
    -> infect_room(Room)
    ;  true
    ).

%% infection_check(+Room)
%  Called every time Jesse enters a room.
%  Handles death_room instant-kill, weapon-pickup grace turn,
%  and ordinary random infection.
infection_check(Room) :-
    ( Room = death_room
    -> assertz(game_over),
       highlight_text(""),
       highlight_text("╔═══════════════════════════════════╗"),
       highlight_text("║           GAME  OVER              ║"),
       highlight_text("╚═══════════════════════════════════╝"),
       normal_text("The Death Room claims you. Some doors should never be opened."),
       normal_text("Type 'restart' to try again.")
    ; weapon_just_taken          % skip infection on the turn the weapon was picked up
    -> retract(weapon_just_taken)
    ; has(jesse, service_weapon), infectable_room(Room)
    -> maybe_infect(Room)
    ; true
    ).

%% on_hiss_defeated(+Room)
%  When an infection entity is killed, clear the infected flag
%  and spawn a health kit reward.
on_hiss_defeated(Room) :-
    ( hiss_infected(Room)
    -> retract(hiss_infected(Room)),
       assertz(object(health_kit, Room)),
       room_name(Room, RoomName),
       atomic_list_concat(['A health kit has appeared in ', RoomName, '!'], Msg),
       tip_text(Msg)
    ; true
    ).

/* ============================================
      MOVEMENT  —  move(+Actor, +Dir, -Result)
      Result is either `moved` or `blocked`.

      Clauses are ordered — Prolog tries them
      top to bottom and the FIRST matching cut
      clause wins.  The order is:

        1. Street wandering flavour
           Catches any invalid direction while
           Jesse is on the street and delegates
           to funny_outside_message/0.

        2. Combat block
           If a live enemy is present, all exits
           are sealed until the enemy is defeated.

        3. Locked-door messages (specific rooms)
           Custom "you need a key" messages for:
             lobby → upper_hall  (requires keys)
             lobby → lab77       (requires lab77_key)
             janitor_hall → east (requires service_weapon)
             solitary → east     (requires dylans_cell_key)

        4. Standard movement
           Calls connected/3 to find the target
           room, updates location/2, and runs
           infection_check/1 for Jesse.

        5. Dead-end fallback
           Prints "You can't go that way."
   ============================================ */

%% Street wandering — flavour messages instead of silent failure
move(jesse, Dir, blocked) :-
    location(jesse, street),
    Dir \= enter,
    \+ connected(street, _, Dir), !,
    funny_outside_message.

%% Block movement while a live enemy is in the room
move(jesse, _, blocked) :-
    location(jesse, Room),
    living_enemy_here(Room), !,
    highlight_text("You can't leave — there's still an enemy here!"),
    findall(N, (
        location(E, Room), is_hiss_enemy(E),
        has(jesse, service_weapon), enemy_display_name(E, N)
    ), Ns),
    forall(member(N, Ns), (
        format(string(S), "Enemy spotted: ~w", [N]),
        highlight_text(S)
    )),
    tip_text("Defeat the enemy before moving on. Use 'attack'.").

%% Locked doors with explanatory messages
move(jesse, north, blocked) :-
    location(jesse, lobby), \+ has(jesse, keys), !,
    highlight_text("The door to the upper hall is locked. You need keys to open it.").

move(jesse, west, blocked) :-
    location(jesse, lobby), \+ has(jesse, lab77_key), !,
    highlight_text("The door to Lab 77 is sealed and locked. You need a key to open it.").

move(jesse, east, blocked) :-
    location(jesse, janitor_hall), \+ has(jesse, service_weapon), !,
    speak(ahti, "'The Service Weapon... you will need it. The deeper places demand it. \
Without it, the shadows will consume you. Go. Retrieve what was left behind.'").

move(jesse, east, blocked) :-
    location(jesse, solitary), \+ has(jesse, dylans_cell_key), !,
    highlight_text("A heavy reinforced door bars the way east. There's a keyhole — but no key."),
    normal_text("Whatever's behind it has been locked tight for a very long time.").

%% Standard movement — update location and run infection check
move(Actor, Dir, moved) :-
    location(Actor, Room),
    connected(Room, Next, Dir), !,
    retract(location(Actor, Room)),
    assertz(location(Actor, Next)),
    ( Actor = jesse -> infection_check(Next) ; true ).

%% Fallback — direction not connected
move(_, _, blocked) :-
    normal_text("You can't go that way.").

/* ============================================
      FUNNY OUTSIDE MESSAGES
      Escalating flavour text when Jesse tries
      to wander away from the Bureau entrance.
   ============================================ */

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

%% funny_outside_message
%  Increment counter and show the appropriate message.
funny_outside_message :-
    outside_attempts(N),
    succ(N, N1),
    retract(outside_attempts(N)),
    assertz(outside_attempts(N1)),
    outside_message(N1).

/* ============================================
      ITEMS — list, take, look at, unlock, shield
      Items are stored as object(Item, Room) facts
      and transferred to has(jesse, Item) on pickup.
   ============================================ */

%% list_items(+Room)
%  Print all items currently on the floor in Room.
%  Shows nothing if the room is empty.
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

%% take_item(+Item)
%  Case-insensitive item pickup — matches the atom the player typed
%  against all objects in the current room, tolerating naive plurals
%  (e.g. "health_kits" → health_kit).
%  Delegates to apply_take/2 for item-specific pickup effects.
%  Prints an error if no matching item is found in the room.
take_item(Item) :-
    location(jesse, Room),
    downcase_atom(Item, ItemAtom),
    findall(Obj, object(Obj, Room), Objects),
    member(MatchObj, Objects),
    downcase_atom(MatchObj, ObjAtom),
    ( ObjAtom = ItemAtom
    ; atom_concat(ItemAtom, 's', ObjAtom)
    ; atom_concat(ObjAtom,  's', ItemAtom)
    ), !,
    apply_take(MatchObj, Room).

take_item(Item) :-
    format(atom(Msg), "There's no ~w here to take.", [Item]),
    normal_text(Msg).

%% apply_take(+Item, +Room)
%  Item-specific pickup effects.  Clauses are ordered; each removes
%  the object fact and asserts has(jesse, Item).

%  health_upgrade — permanently raises max HP by 5 and heals 5 HP
%                   (cannot exceed the new max).
apply_take(health_upgrade, Room) :-
    max_health(jesse, MaxHP),
    retract(object(health_upgrade, Room)),
    NewMaxHP is MaxHP + 5,
    retract(max_health(jesse, MaxHP)),
    assertz(max_health(jesse, NewMaxHP)),
    health(jesse, HP),
    NewHP is min(NewMaxHP, HP + 5),
    retract(health(jesse, HP)),
    assertz(health(jesse, NewHP)),
    assertz(has(jesse, health_upgrade)),
    format(atom(M), "Max health increased from ~w to ~w/~w", [MaxHP, NewHP, NewMaxHP]),
    normal_text(M).

%  charge_upgrade — permanently raises max weapon charge by 2
%                   and restores 2 charges (cannot exceed new max).
apply_take(charge_upgrade, Room) :-
    max_weapon_charge(jesse, MaxCharge),
    retract(object(charge_upgrade, Room)),
    NewMaxCharge is MaxCharge + 2,
    retract(max_weapon_charge(jesse, MaxCharge)),
    assertz(max_weapon_charge(jesse, NewMaxCharge)),
    weapon_charge(jesse, Charge),
    NewCharge is min(NewMaxCharge, Charge + 2),
    retract(weapon_charge(jesse, Charge)),
    assertz(weapon_charge(jesse, NewCharge)),
    assertz(has(jesse, charge_upgrade)),
    format(atom(M), "Max weapon charge increased from ~w to ~w/~w", [MaxCharge, NewCharge, NewMaxCharge]),
    normal_text(M).

%  sense — grants persistent awareness of enemies in adjacent rooms.
apply_take(sense, Room) :-
    retract(object(sense, Room)),
    assertz(has(jesse, sense)),
    assertz(sense_active),
    highlight_text("You pick up the resonance sensor. It pulses once in your hand."),
    normal_text("A faint awareness settles at the edge of your perception — \
a low hum that sharpens whenever something hostile is nearby."),
    tip_text("Sense active: you will be warned of enemies in adjacent rooms.").

%  health_kit — restores HP to max; does nothing if already full.
apply_take(health_kit, Room) :-
    health(jesse, HP), max_health(jesse, MaxHP),
    retract(object(health_kit, Room)),
    ( HP >= MaxHP
    -> highlight_text("You are already at full health.")
    ;  retract(health(jesse, HP)),
       assertz(health(jesse, MaxHP)),
       assertz(has(jesse, health_kit)),
       format(atom(M), "Health restored to ~w/~w", [MaxHP, MaxHP]),
       normal_text(M)
    ).

%  service_weapon — equips the weapon, spawns hiss_guard in upper_hall
%                   with 30 HP, and sets weapon_just_taken to skip the
%                   infection check on this same turn.
apply_take(service_weapon, Room) :-
    retract(object(service_weapon, Room)),
    assertz(has(jesse, service_weapon)),
    normal_text("You take the Service Weapon."),
    assertz(location(hiss_guard, upper_hall)),
    assertz(health(hiss_guard, 30)),
    assertz(location(hiss_spawn, lobby)),
    assertz(health(hiss_spawn, 20)),
    assertz(weapon_just_taken),  % suppress infection check this turn
    highlight_text("A distant screech echoes through the building...").

%  weapon_form — merges paranatural resonance into the Service Weapon;
%               triples damage but costs 3 weapon charges per shot.
apply_take(weapon_form, Room) :-
    retract(object(weapon_form, Room)),
    assertz(has(jesse, weapon_form)),
    assertz(weapon_form_active),
    normal_text("You reach out and grasp the resonance form. It writhes in your hands,"),
    normal_text("then stills — merging with the Service Weapon. The weapon feels heavier now."),
    normal_text("Hungrier. You can feel its appetite."),
    highlight_text("Weapon Form absorbed. Damage ×3. Each shot now costs 3 charges.").

%  Generic — no special logic; just removes object and adds to inventory.
apply_take(Item, Room) :-
    retract(object(Item, Room)),
    assertz(has(jesse, Item)),
    format(atom(M), "You take the ~w.", [Item]),
    normal_text(M).

%% look_at(+Obj)
%  Examine a specific object. Only cat_statue has a custom description.
look_at(cat_statue) :- !,
    ( has(jesse, cat_statue)
    -> normal_text("A small stone cat. It sits perfectly still in your hands. \
Its eyes seem to follow you. You get the sense it wants to be somewhere specific.")
    ;  location(jesse, Room),
       ( object(cat_statue, Room) ; cat_statue_placed, Room = atrium )
    -> normal_text("A small stone cat rests on the plinth. The floor hums softly beneath it.")
    ;  normal_text("You don't see a cat statue here.")
    ).

look_at(Obj) :-
    format(atom(Msg), "You examine the ~w closely, but see nothing special.", [Obj]),
    normal_text(Msg).

%% unlock_item(+Item, +Code)
%  Unlock the locked_box at the food_vendor with the correct code.
%  Code BUREAU47 yields the lab77_key.
%  Called with Code = none when the player types 'unlock locked_box'
%  without a code (prints usage hint instead).
unlock_item(Item, Code) :-
    atom_string(Item, S), string_lower(S, SL), atom_string(ItemAtom, SL),
    ( ItemAtom = locked_box
    -> ( Code = none
       -> location(jesse, food_vendor), object(locked_box, food_vendor), !,
          tip_text("Usage: unlock locked_box <code>")
       ;  location(jesse, food_vendor), object(locked_box, food_vendor), !,
          ( Code == bureau47
          -> retract(object(locked_box, food_vendor)),
             assertz(has(jesse, lab77_key)),
             highlight_text("You unlock the box and find a Lab 77 key inside!"),
             tip_text("The lab77_key has been added to your inventory.")
          ;  color_ln(red, "That's not the right code.")
          )
       )
    ;  format(string(ErrS), "You can't unlock the ~w.", [Item]),
       color_ln(red, ErrS)
    ).

%% use_shield
%  Activate the paranatural shield for one hit absorption.
%  Guards (in order):
%    • Jesse doesn't own it yet       → inform player.
%    • Shield is already active       → remind player.
%    • No live enemy in current room  → discourage wasting it.
%    • Otherwise                      → assert shield_active.
use_shield :-
    ( \+ has(jesse, shield)
    -> normal_text("You don't have a shield to use.")
    ;  shield_active
    -> highlight_text("Your shield is already active — it will absorb the next hit.")
    ;  location(jesse, Room), \+ living_enemy_here(Room)
    -> normal_text("There's no enemy here. Save the shield for when you need it.")
    ;  assertz(shield_active),
       highlight_text("You raise the hexagonal shield. A pale blue barrier crackles around you."),
       tip_text("The shield will absorb the next enemy hit, then dissipate.")
    ).

/* ============================================
      MAP DISPLAY
      ASCII relative map centred on Jesse's
      current room; shows N/S/E/W neighbours
      with locked status where applicable.
   ============================================ */

%% map_label_center(+Room, -Label)
%  Format the current room as [>room<].
map_label_center(Room, Label) :-
    format(atom(Label), "[>~w<]", [Room]).

%% label_with_status(+Name, +Status, -Label)
%  Append "(locked)" to label if Status = locked.
label_with_status(Name, locked, Label) :- !,
    format(atom(Label), "[~w] (locked)", [Name]).
label_with_status(Name, _, Label) :-
    format(atom(Label), "[~w]", [Name]).

%% dir_equiv(+Cardinal, ?ConnDir)
%  Map canonical directions to their connection aliases.
dir_equiv(north, north). dir_equiv(north, enter).
dir_equiv(south, south). dir_equiv(south, exit).
dir_equiv(east,  east).
dir_equiv(west,  west).

%% neighbor(+Current, +Cardinal, -DisplayNext, -Status)
%  Find the neighbouring room in the given cardinal direction.
%  Returns Status = open | locked.
neighbor(Current, Cardinal, DisplayNext, Status) :-
    dir_equiv(Cardinal, ConnDir),
    ( connected(Current, Next, ConnDir)
    -> ( Next = lab77_locked
       -> DisplayNext = lab77, Status = locked
       ;  DisplayNext = Next, Status = open
       )
    ;  clause(connected(Current, Alt, ConnDir), _)
    -> ( Alt = lab77_locked
       -> DisplayNext = lab77, Status = locked
       ;  DisplayNext = Alt, Status = locked
       )
    ;  fail
    ).

%% spaces(+N, -Atom)
%  Build an atom of N space characters.
spaces(N, S) :-
    length(Cs, N),
    maplist(=(0' ), Cs),
    atom_chars(S, Cs).

%% map_line(+Fmt, +Args)
%  Format and print a single map line in cyan.
map_line(Fmt, Args) :-
    format(string(S), Fmt, Args),
    map_text(S).

%% center_start(+WLabel, -Start)
%  Calculate the column offset for the center room given the west label width.
center_start("",     0) :- !.
center_start(WLabel, Start) :-
    atom_length(WLabel, WL),
    Start is WL + 5.

%% show_map(+Current)
%  Render the full relative map for the current room.
show_map(Current) :-
    map_label_center(Current, Center),
    ( neighbor(Current, north, N, NS) -> label_with_status(N, NS, NLabel) ; NLabel = "" ),
    ( neighbor(Current, south, S, SS) -> label_with_status(S, SS, SLabel) ; SLabel = "" ),
    ( neighbor(Current, east,  E, ES) -> label_with_status(E, ES, ELabel) ; ELabel = "" ),
    ( neighbor(Current, west,  W, WS) -> label_with_status(W, WS, WLabel) ; WLabel = "" ),

    atom_length(Center, CL),
    center_start(WLabel, CStart),
    ArrowCol is CStart + CL // 2,
    spaces(ArrowCol, ArrowPad),

    map_text(""),
    map_text("Relative Map:"),

    ( NLabel \= ""
    -> atom_length(NLabel, NL),
       NCol is max(0, ArrowCol - NL // 2),
       spaces(NCol, NPad),
       map_line("~w~w", [NPad, NLabel]),
       map_line("~w^",  [ArrowPad]),
       map_line("~w|",  [ArrowPad])
    ; true ),

    ( WLabel \= "", ELabel \= ""
    -> map_line("~w <-- ~w --> ~w", [WLabel, Center, ELabel])
    ; WLabel \= ""
    -> map_line("~w <-- ~w", [WLabel, Center])
    ; ELabel \= ""
    -> map_line("~w --> ~w", [Center, ELabel])
    ;  map_line("~w", [Center])
    ),

    ( SLabel \= ""
    -> atom_length(SLabel, SL),
       SCol is max(0, ArrowCol - SL // 2),
       spaces(SCol, SPad),
       map_line("~w|",  [ArrowPad]),
       map_line("~wv",  [ArrowPad]),
       map_line("~w~w", [SPad, SLabel])
    ; true ),

    map_text(""),
    ( room_name(Current, RoomName) -> true ; RoomName = Current ),
    format(atom(LocMsg), "Jesse is at: ~w", [RoomName]),
    map_text(LocMsg),
    map_text("").

/* ============================================
      DESCRIBE CURRENT ROOM
      Called on entry and with 'look'.
      Renders map, description, notes, thoughts,
      occupants, items, then enemy announcements.
   ============================================ */

describe_here :-
    location(jesse, Room), !,
    show_map(Room),
    description(Room, Desc),
    normal_text(Desc),
    ( Room = food_vendor
    -> tip_text("Tip: go west to return to the street entrance."),
       tip_text("Tip: try 'unlock locked_box <code>' if you find a clue.")
    ; true
    ),
    list_notes(Room),
    list_thoughts(Room),
    list_occupants(Room),
    list_items(Room),
    announce_enemies(Room),
    show_sense(Room).

%% show_sense(+Room)
%  If sense_active, scan all adjacent rooms for live enemies
%  and warn the player about each one found.
show_sense(Room) :-
    sense_active, !,
    findall(Next, (
        connected(Room, Next, _),
        living_enemy_here(Next)
    ), DangerRooms),
    ( DangerRooms \= []
    -> tip_text("[ SENSE ] Hostile presence detected nearby:"),
       forall(member(DR, DangerRooms), (
           room_name(DR, RName),
           format(string(Msg), "  Caution: enemies in ~w — proceed carefully.", [RName]),
           tip_text(Msg)
       ))
    ; true
    ).
show_sense(_).

%% list_occupants(+Room)
%  Show friendly NPCs in the room with a header and talk tip.
%  Hiss enemies are handled separately by announce_enemies/1.
list_occupants(Room) :-
    findall(N, (location(N, Room), N \= jesse), Others),
    ( Others = [] -> true
    ;  include(visible_npc, Others, Visible),
       exclude(is_hiss_enemy, Visible, Friendlies),
       ( Friendlies \= []
       -> writeln(""),
          highlight_text("People here:"),
          maplist(announce_friendly_npc, Friendlies),
          highlight_text("Use 'talk <name>' to speak with them."),
          writeln("")
       ; true
       )
    ).

announce_friendly_npc(Name) :-
    format(string(S), "  ~w", [Name]),
    note_text(S).

/* ============================================
      HELP / STATUS COMMANDS
   ============================================ */

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
    normal_text("Combat:    attack | attack <enemy>"),
    normal_text("Shield:    shield | use shield | activate shield"),
    normal_text("Skip:      skip | wait (recharge weapon; enemy retaliates)"),
    normal_text("Health:    health | status"),
    normal_text("Charge:    charge (show weapon charge)"),
    normal_text("Restart:   restart | new game | start over"),
    normal_text("Help:      help"),
    normal_text("Quit:      quit"),
    map_text("----------------"),
    highlight_text("OBJECTIVE: Find your estranged brother, Dylan, in the mysterious Oldest House."),
    map_text("================").

%% show_health — print Jesse's current and max HP
show_health :-
    health(jesse, HP), max_health(jesse, MaxHP),
    format(atom(Msg), "Health: ~w/~w", [HP, MaxHP]),
    highlight_text(Msg).

%% show_charge — print Service Weapon charge if equipped
show_charge :-
    ( has(jesse, service_weapon)
    -> weapon_charge(jesse, C), max_weapon_charge(jesse, MC),
       format(atom(Msg), "Service Weapon Charge: ~w/~w", [C, MC]),
       highlight_text(Msg)
    ;  highlight_text("You need to pick up the Service Weapon first.")
    ).

%% show_inventory — list all items Jesse is carrying
show_inventory :-
    findall(I, has(jesse, I), Items),
    ( Items = []
    -> highlight_text("Your inventory is empty.")
    ;  atomic_list_concat(Items, ', ', ItemStr),
       highlight_text("You are carrying:"),
       note_text(ItemStr)
    ).

/* ============================================
      PARSER  —  parse(+Tokens, -Command)
      Maps a list of lowercase atom tokens
      (produced by the game loop / server handler)
      to a command term consumed by dispatch/1.

      Grammar summary:
        Movement : go/move/walk + Dir
                   enter | go inside | go in
        Look     : look | look at <Obj>
        Map      : map | show map
        Talk     : talk ahti | talk vendor | talk dylan
        Attack   : attack | attack <enemy>
        Take     : take <Item> | pick up <Item>
        Inventory: inventory | inv | i
        Read     : read | read note | read notes
                   read <Name> | read note <Name>
        Think    : think | think <Name>
        Place    : place <Item> | put <Item> down
                   put down <Item>
        Unlock   : unlock <Item> | unlock <Item> <Code>
        Shield   : shield | use shield | activate shield
        Skip     : skip | wait
        Status   : health | status | charge
        Restart  : restart | new game | start over
        Misc     : help | quit

      Any token list that doesn't match any clause
      causes parse/2 to fail; the caller handles that
      by printing "I don't understand."
   ============================================ */

parse([go,   Dir], go(Dir)).
parse([move, Dir], go(Dir)).
parse([walk, Dir], go(Dir)).

parse([look],           look).
parse([look, at, Obj],  look_at(Obj)).

parse([talk, ahti],       talk(ahti)).
parse([talk, vendor],     talk(vendor)).
parse([talk, dylan],      talk(dylan)).
parse([talk, drenchtov],  talk(drenchtov)).
parse([talk, hartwell],   talk(hartwell)).
parse([talk, okoro],      talk(okoro)).

parse([attack],               attack).
parse([attack, hiss_spawn],   attack(hiss_spawn)).
parse([attack, hiss_guard],   attack(hiss_guard)).
parse([attack, hiss_guard_b], attack(hiss_guard_b)).
parse([attack, hiss_brute],   attack(hiss_brute)).
parse([attack, hiss_boss],    attack(hiss_boss)).

parse([take, Item],     take(Item)).
parse([pick, up, Item], take(Item)).

parse([inventory], inventory).
parse([inv],       inventory).
parse([i],         inventory).

parse([quit],   quit).
parse([help],   help).
parse([health], health).
parse([status], health).
parse([charge], charge).
parse([skip],   skip).
parse([wait],   skip).

parse([enter],      go(enter)).
parse([go, inside], go(enter)).
parse([go, in],     go(enter)).

parse([read],              read(all)).
parse([read, note],        read(all)).
parse([read, notes],       read(all)).
parse([read, Name],        read(Name)).
parse([read, note,  Name], read(Name)).
parse([read, notes, Name], read(Name)).

parse([map],       map).
parse([show, map], map).

parse([unlock, Item],       unlock(Item, none)).
parse([unlock, Item, Code], unlock(Item, Code)).

parse([think],       think(here)).
parse([think, Name], think(Name)).

parse([place, Item],     place(Item)).
parse([put, Item, down], place(Item)).
parse([put, down, Item], place(Item)).

parse([restart],     restart).
parse([new, game],   restart).
parse([start, over], restart).

parse([shield],           shield).
parse([use, shield],      shield).
parse([activate, shield], shield).

/* ============================================
      COMMAND DISPATCH  —  dispatch(+Command)
      Executes a command term produced by parse/2.

      Each clause is deterministic (cut after
      the first match) to prevent backtracking
      into later clauses after a command runs.

      dispatch(go(Dir)) is the central navigation
      handler: it calls move/3, then re-renders
      the room description only on a successful
      move and only if game_over has not been set
      (e.g. death_room instant kill).

      dispatch(attack) resolves the target
      automatically by checking living_enemy_here/1
      and testing enemies in priority order:
        boss > brute > guard_b > guard > spawn > infection.
   ============================================ */

dispatch(look)          :- !, describe_here.
dispatch(look_at(Obj))  :- !, look_at(Obj).
dispatch(map)           :- !, location(jesse, Room), show_map(Room).
dispatch(help)          :- !, show_help.
dispatch(health)        :- !, show_health.
dispatch(charge)        :- !, show_charge.
dispatch(inventory)     :- !, show_inventory.

dispatch(go(Dir)) :- !,
    move(jesse, Dir, Result),
    ( game_over      -> true
    ; Result = moved -> describe_here
    ; true
    ).

dispatch(talk(ahti))       :- !, talk_to(ahti).
dispatch(talk(vendor))     :- !, talk_to(vendor).
dispatch(talk(dylan))      :- !, talk_to(dylan).
dispatch(talk(drenchtov))  :- !, talk_to(drenchtov).
dispatch(talk(hartwell))   :- !, talk_to(hartwell).
dispatch(talk(okoro))      :- !, talk_to(okoro).

dispatch(take(Obj))          :- !, take_item(Obj).
dispatch(read(Name))         :- !, read_notes(Name).
dispatch(think(Name))        :- !, think_thought(Name).
dispatch(place(Item))        :- !, place_item(Item).
dispatch(unlock(Item, Code)) :- !, unlock_item(Item, Code).
dispatch(shield)             :- !, use_shield.
dispatch(skip)               :- !, skip_turn.
dispatch(restart)            :- !, restart_game.
dispatch(quit)               :- !, normal_text("You step back from the House.").

%% Generic attack — targets highest-priority live enemy in the room
dispatch(attack) :- !,
    location(jesse, Room),
    ( living_enemy_here(Room)
    -> ( location(hiss_boss,    Room), health(hiss_boss,    HP0), HP0 > 0 -> combat(jesse, hiss_boss)
       ; location(hiss_brute,   Room), health(hiss_brute,   HP1), HP1 > 0 -> combat(jesse, hiss_brute)
       ; location(hiss_guard_b, Room), health(hiss_guard_b, HP2), HP2 > 0 -> combat(jesse, hiss_guard_b)
       ; location(hiss_guard,   Room), health(hiss_guard,   HP3), HP3 > 0 -> combat(jesse, hiss_guard)
       ; location(hiss_spawn,   Room), health(hiss_spawn,   HP4), HP4 > 0 -> combat(jesse, hiss_spawn)
       ; location(E, Room), atom_concat(hiss_infection_, _, E),
         health(E, EHP), EHP > 0 -> combat(jesse, E)
       ; normal_text("There's nothing to attack here.")
       )
    ;  normal_text("There's nothing to attack here.")
    ).

dispatch(attack(hiss_spawn))   :- !, combat(jesse, hiss_spawn).
dispatch(attack(hiss_guard))   :- !, combat(jesse, hiss_guard).
dispatch(attack(hiss_guard_b)) :- !, combat(jesse, hiss_guard_b).
dispatch(attack(hiss_brute))   :- !, combat(jesse, hiss_brute).
dispatch(attack(hiss_boss))    :- !, combat(jesse, hiss_boss).

%% Fallback — unknown command term (should not normally be reached)
dispatch(Cmd) :-
    format("I don't know how to handle: ~w~n", [Cmd]).

/* ============================================
      GAME LOOP  —  game_loop/0
      The main read-eval-print loop for standalone
      play.  Each iteration:
        1. Prints "> " prompt.
        2. Reads a line from user_input.
        3. Lowercases and splits into tokens.
        4. Cleans each token with clean_token_smart/2.
        5. Converts strings to atoms.
        6. If game_over is set, only restart/quit
           are accepted; all other input shows the
           death message and loops.
        7. Otherwise attempts parse/2; on failure
           prints "I don't understand." and loops.
        8. On 'quit' the loop terminates; otherwise
           tail-recurses.
   ============================================ */

game_loop :-
    write("> "),
    read_line_to_string(user_input, Line),
    string_lower(Line, Lower),
    split_string(Lower, " ", " \t", Words0),
    maplist(clean_token_smart, Words0, Words),
    maplist(atom_string, Tokens, Words),
    ( game_over
    -> ( parse(Tokens, restart) -> dispatch(restart), game_loop
       ; parse(Tokens, quit)    -> dispatch(quit)
       ; normal_text("You are dead. Type 'restart' to try again or 'quit' to exit."),
         game_loop
       )
    ;  ( parse(Tokens, Command)
       -> ignore(dispatch(Command)),
          ( Command = quit -> true ; game_loop )
       ;  writeln("I don't understand."),
          game_loop
       )
    ).

/* ============================================
      GAME START  —  start/0
      Entry point called by initialization/2 in
      standalone mode.  Renders the opening scene
      (map, intro text, tips, room description,
      notes, thoughts, occupants, items) and then
      enters game_loop/0.
   ============================================ */

start :-
    location(jesse, Room),
    show_map(Room),
    normal_text("You arrive at the Federal Bureau of Control."),
    normal_text("The building looms above you, humming with a strange, low resonance."),
    normal_text("Something pulls you toward the entrance."),
    tip_text("Tip: try 'enter' or 'go north' to go inside. You can also go east to visit the food vendor."),
    tip_text("Tip: try 'help' to list all available commands."),
    description(Room, Desc),
    normal_text(Desc),
    list_notes(Room),
    list_thoughts(Room),
    list_occupants(Room),
    list_items(Room),
    game_loop.

/* ============================================
      RESTART  —  restart_game/0
      Wipes all dynamic state introduced at
      game start or accumulated during play,
      then re-asserts the exact same initial
      configuration as the top-level assertz
      directives at file load time.

      Called by:
        dispatch(restart)       — from game loop
        server.pl reset_game/0  — from web handler

      Note: does NOT call start/0 or game_loop/0.
      In standalone mode the game_loop continues
      after dispatch(restart) returns.  In web
      mode server.pl calls init_game_output/0
      separately after reset_game/0.
   ============================================ */

restart_game :-
    % --- Clear all runtime state ---
    retractall(game_over),
    retractall(health_kit_tip_shown),
    retractall(attack_tip_shown),
    retractall(cat_statue_placed),
    retractall(hiss_infected(_)),
    retractall(weapon_just_taken),
    retractall(shield_active),
    retractall(weapon_form_active),
    retractall(sense_active),
    retractall(location(_, _)),
    retractall(health(_, _)),
    retractall(max_health(_, _)),
    retractall(weapon_charge(_, _)),
    retractall(max_weapon_charge(_, _)),
    retractall(has(_, _)),
    retractall(read_note(_, _)),
    retractall(outside_attempts(_)),
    retractall(object(_, _)),

    % --- Re-assert initial locations ---
    assertz(location(jesse,        street)),
    assertz(location(ahti,         janitor_hall)),
    assertz(location(drenchtov,    utility_bay)),
    assertz(object(health_kit,     utility_bay)),
    assertz(location(hiss_brute,   atrium)),
    assertz(location(hiss_guard_b, containment_hall)),
    assertz(location(hiss_boss,    solitary)),
    assertz(location(vendor,       food_vendor)),
    assertz(location(dylan,        dylans_cell)),

    % --- Re-assert health and stats ---
    assertz(health(jesse,        100)),
    assertz(max_health(jesse,    100)),
    assertz(health(hiss_brute,    50)),
    assertz(health(hiss_guard_b,  30)),
    assertz(health(hiss_boss,    100)),
    assertz(weapon_charge(jesse,     10)),
    assertz(max_weapon_charge(jesse, 10)),
    assertz(outside_attempts(0)),

    % --- Re-assert item placement ---
    assertz(object(keys,           lobby)),
    assertz(object(service_weapon, directors_office)),
    assertz(object(health_kit,     anteroom)),
    assertz(object(health_upgrade, ops_room)),
    assertz(object(locked_box,     food_vendor)),
    assertz(object(health_kit,     north_alley)),
    assertz(object(smash,          lab77)),
    assertz(object(health_kit,     archive_bay)),
    assertz(object(health_upgrade, secret_chamber)),
    assertz(object(health_upgrade, toilets)),
    assertz(object(charge_upgrade, pipe_room)),
    assertz(object(charge_upgrade, atrium)),
    assertz(object(health_kit,     rejuvenation_room)),
    assertz(object(health_upgrade, rejuvenation_room)),
    assertz(object(charge_upgrade, sub_lab)),
    assertz(object(weapon_form,    resonance_lab)),
    assertz(object(health_kit,     lobby)),
    assertz(object(health_kit,     security_post)),
    assertz(object(health_kit,     records_room)),
    assertz(object(sense,          records_room)),
    assertz(object(health_kit,     containment_hall)),
    assertz(object(charge_upgrade, cell_annex)),
    assertz(object(health_kit,     watch_post)),
    assertz(object(health_kit,     solitary)),
    assertz(object(cat_statue,     upper_hall)),
    assertz(object(flower,         street)),
    assertz(object(shield,         demolition_room)),
    assertz(object(health_kit,     blast_corridor)),
    assertz(object(charge_upgrade, evidence_vault)).

/* ============================================
      ENTRY POINT
      Only active in standalone mode — server.pl
      overrides the output predicates before
      loading this file, so the guard prevents
      the initialization directive from firing
      when running under the web server.
   ============================================ */

:- if(\+ current_module(server)).
:- initialization(start, main).
:- endif.

