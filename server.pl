:- module(server, []).

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_files)).

/* --- Output buffer --- */
:- dynamic output_buffer/1.
:- dynamic last_buf_style/1.

output_buffer([]).
last_buf_style(none).

buf_add(Style, Text) :-
    % insert a spacer whenever the style changes (but not on first line)
    last_buf_style(Last),
    ( Last \= none, Last \= Style
    -> retract(output_buffer(Buf0)),
       assertz(output_buffer([_{text:"", style:spacer}|Buf0]))
    ; true
    ),
    retract(output_buffer(Buf)),
    assertz(output_buffer([_{text:Text, style:Style}|Buf])),
    retractall(last_buf_style(_)),
    assertz(last_buf_style(Style)).

buf_flush(Lines) :-
    retract(output_buffer(Buf)),
    assertz(output_buffer([])),
    retractall(last_buf_style(_)),
    assertz(last_buf_style(none)),
    reverse(Buf, Lines).

/* --- Output predicates (web versions) --- */
:- dynamic last_color/1.
last_color(default).

normal_text(Text)    :- buf_add(normal, Text).
highlight_text(Text) :- buf_add(highlight, Text).
map_text(Text)       :- buf_add(map, Text).
tip_text(Text)       :- buf_add(tip, Text).
note_text(Text)      :- buf_add(note, Text).
speak(_, Text)       :- buf_add(speak, Text).

color_ln(red, Text)    :- buf_add(note, Text).
color_ln(yellow, Text) :- buf_add(highlight, Text).
color_ln(cyan, Text)   :- buf_add(map, Text).
color_ln(_, Text)      :- buf_add(normal, Text).

% space_if_color_changed is handled automatically by buf_add style tracking
space_if_color_changed.

% Catch stray writeln calls — ignore empty strings
writeln(Text) :-
    ( Text = "" ; Text = '' ; Text = [] )
    -> true
    ;  term_to_atom(Text, A), atom_string(A, S),
       ( S = "" -> true ; buf_add(normal, S) ).

/* --- Load game AFTER output overrides --- */
:- [control].

/* --- Routes --- */
:- http_handler(root(.),            http_redirect(moved, '/index.html'), []).
:- http_handler(root('index.html'), serve_index,   []).
:- http_handler(root(start),        handle_start,  [method(post)]).
:- http_handler(root(command),      handle_command,[method(post)]).

serve_index(Request) :-
    http_reply_file('index.html', [], Request).

handle_start(_Request) :-
    reset_game,
    init_game_output,
    buf_flush(Lines),
    reply_json_dict(_{lines: Lines, ok: true}).

handle_command(Request) :-
    http_read_json_dict(Request, Dict),
    Input = Dict.input,
    string_lower(Input, Lower),
    split_string(Lower, " ", " \t", Words0),
    maplist(clean_token_smart, Words0, Words),
    maplist(atom_string, Tokens, Words),
    ( Tokens \= [''] ->
        ( parse(Tokens, Command)
        -> dispatch(Command)
        ;  buf_add(error, "I don't understand.")
        )
    ; true
    ),
    buf_flush(Lines),
    reply_json_dict(_{lines: Lines, ok: true}).

init_game_output :-
    location(jesse, Room),
    show_map(Room),
    normal_text("You arrive at the Federal Bureau of Control."),
    normal_text("The building looms above you, humming with a strange, low resonance."),
    normal_text("Something pulls you toward the entrance."),
    tip_text("Tip: try 'enter' or 'go north' to go inside The Oldest House. Try 'help' for all commands."),
    description(Room, Desc),
    normal_text(Desc),
    list_notes(Room),
    list_items(Room),
    list_occupants(Room).

reset_game :-
    retractall(location(_, _)),
    retractall(health(_, _)),
    retractall(max_health(_, _)),
    retractall(weapon_charge(_, _)),
    retractall(max_weapon_charge(_, _)),
    retractall(has(_, _)),
    retractall(read_note(_, _)),
    retractall(outside_attempts(_)),
    retractall(object(_, _)),
    retractall(game_over),
    retractall(hiss_infected(_)),
    retractall(last_color(_)),
    retractall(last_buf_style(_)),
    assertz(last_color(default)),
    assertz(last_buf_style(none)),
    assertz(location(jesse, street)),
    assertz(location(ahti, janitor_hall)),
    % hiss_guard spawns when service_weapon is picked up
    assertz(location(hiss_brute, atrium)),
    assertz(location(hiss_guard_b, containment_hall)),
    assertz(location(vendor, food_vendor)),
    assertz(health(jesse, 100)),
    assertz(max_health(jesse, 100)),
    assertz(health(hiss_brute, 50)),
    assertz(health(hiss_guard_b, 30)),
    assertz(weapon_charge(jesse, 10)),
    assertz(max_weapon_charge(jesse, 10)),
    assertz(outside_attempts(0)),
    assertz(object(keys, lobby)),
    assertz(object(service_weapon, directors_office)),
    assertz(object(locked_box, food_vendor)),
    assertz(object(smash, lab77)),
    assertz(object(health_upgrade, secret_chamber)),
    assertz(object(health_upgrade, toilets)),
    assertz(object(charge_upgrade, atrium)),
    assertz(object(health_kit, lobby)),
    assertz(object(health_kit, security_post)),
    assertz(object(health_kit, records_room)).

:- initialization(
    ( reset_game,
      http_server(http_dispatch, [port(8081)]),
      format("My Control Text Adventure Adaption Game Server is running at http://localhost:8081/~n"),
      thread_get_message(stop)
    ), main).
