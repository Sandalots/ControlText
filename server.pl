:- module(server, []).

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_files)).

/* --- Output buffer --- */
:- dynamic output_buffer/1.
output_buffer([]).

buf_add(Style, Text) :-
    retract(output_buffer(Buf)),
    assertz(output_buffer([_{text:Text, style:Style}|Buf])).

buf_flush(Lines) :-
    retract(output_buffer(Buf)),
    assertz(output_buffer([])),
    reverse(Buf, Lines).

/* --- Output predicates (web versions) --- */
:- dynamic last_color/1.
last_color(default).

normal_text(Text)    :- buf_add(normal, Text).
highlight_text(Text) :- buf_add(highlight, Text).
map_text(Text)       :- buf_add(map, Text).
tip_text(Text)       :- buf_add(tip, Text).
color_ln(_, Text)    :- buf_add(normal, Text).
space_if_color_changed.
speak(_, Text)       :- buf_add(speak, Text).

% Catch stray writeln/1 calls
writeln(Text) :-
    term_to_atom(Text, A),
    atom_string(A, S),
    buf_add(normal, S).

/* --- Load game AFTER output overrides --- */
:- [control].

/* --- Routes --- */
:- http_handler(root(.),            http_redirect(moved, '/index.html'), []).
:- http_handler(root('index.html'), serve_index,   []).
:- http_handler(root(start),        handle_start,  [method(post)]).
:- http_handler(root(command),      handle_command,[method(post)]).

serve_index(Request) :-
    http_reply_file('index.html', [], Request).

/* --- Handlers --- */

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

/* --- Game init for web --- */

init_game_output :-
    location(jesse, Room),
    show_map(Room),
    normal_text("You arrive at the Federal Bureau of Control."),
    normal_text("The building looms above you, humming with a strange, low resonance."),
    normal_text("Something pulls you toward the entrance."),
    tip_text("Tip: try 'enter' to go inside. Try 'help' for all commands."),
    description(Room, Desc),
    normal_text(Desc),
    list_notes(Room),
    list_occupants(Room),
    list_items(Room).

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
    retractall(last_color(_)),
    assertz(last_color(default)),
    assertz(location(jesse, street)),
    assertz(location(ahti, janitor_hall)),
    assertz(location(hiss_guard, upper_hall)),
    assertz(location(vendor, food_vendor)),
    assertz(health(jesse, 100)),
    assertz(max_health(jesse, 100)),
    assertz(weapon_charge(jesse, 10)),
    assertz(max_weapon_charge(jesse, 10)),
    assertz(health(hiss_guard, 30)),
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
    assertz(object(health_kit, records_room)).

/* --- Start --- */
:- initialization(
    ( reset_game,
      http_server(http_dispatch, [port(8081)]),
      format("Server running at http://localhost:8081/~n"),
      thread_get_message(stop)
    ), main).
