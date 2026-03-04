% HTTP server and web interface for control.pl
:- module(server, []).

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_files)).

:- multifile normal_text/1.
:- multifile highlight_text/1.
:- multifile map_text/1.
:- multifile map_text_bold/1.
:- multifile tip_text/1.
:- multifile note_text/1.
:- multifile speak/2.
:- multifile color_ln/2.
:- multifile space_if_color_changed/0.
:- multifile map_line/2.
:- multifile last_color/1.

:- consult('control.pl').

:- dynamic output_buffer/1.
:- dynamic last_buf_style/1.
:- dynamic prologue_shown/0.

output_buffer([]).
last_buf_style(none).

buf_add(Style, Text) :-
   last_buf_style(Last),
   ( Last \= none, Last \= Style
   -> retract(output_buffer(Buf0)),
      assertz(output_buffer([_{text:"", style:spacer}|Buf0]))
   ; true),

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

:- dynamic last_color/1.
last_color(default).

normal_text(Text)    :- buf_add(normal, Text).
highlight_text(Text) :- buf_add(highlight, Text).
map_text(Text)       :- buf_add(map, Text).
map_text_bold(Text)  :- buf_add('map-bold', Text).
tip_text(Text)       :- buf_add(tip, Text).
note_text(Text)      :- buf_add(note, Text).
speak(_, Text)       :- buf_add(speak, Text).

:- multifile map_line/2.

map_line(Fmt, Args) :-
   format(string(S), Fmt, Args),
   map_text(S).

map_line_with_bold(Text) :-
   ( re_matchsub('(.*?)(\\[[^\\]]*\\])(.*)', Text, Sub, [])

   -> Prefix = Sub.get('1'),
      Location = Sub.get('2'),
      Suffix = Sub.get('3'),

      ( Prefix \= "" -> buf_add(map, Prefix) ; true ),

      buf_add('map-bold', Location),
      map_line_with_bold(Suffix)
   ; ( Text \= "" -> buf_add(map, Text) ; true )
   ).

color_ln(red, Text)    :- buf_add(note, Text).
color_ln(yellow, Text) :- buf_add(highlight, Text).
color_ln(cyan, Text)   :- buf_add(map, Text).
color_ln(_, Text)      :- buf_add(normal, Text).

space_if_color_changed.

writeln(Text) :-
   ( Text = "" ; Text = '' ; Text = [] )
   -> ( last_buf_style(Last),
         ( Last \= none

         -> retract(output_buffer(Buf)),
            assertz(output_buffer([_{text:"", style:spacer}|Buf])),
            retractall(last_buf_style(_)),
            assertz(last_buf_style(none))
         ; true
         )
       )

    ;  term_to_atom(Text, A), atom_string(A, S),
         ( S = "" -> true ; buf_add(normal, S) ).

:- multifile map_line/2.
:- [control].

:- http_handler(root(.),            http_redirect(moved, '/index.html'), []).
:- http_handler(root('index.html'), serve_index,   []).
:- http_handler(root(start),        handle_start,  [method(post)]).
:- http_handler(root(command),      handle_command,[method(post)]).

% helper writer to show my prologue flavour text plus start game button, diff from control.pl as buttons cannot eaisly be implemented there, so better ux version suited for webpage below.
show_prologue_only :-
   writeln(""),
   writeln(""),
   writeln(""),
   normal_text("════════════════════════════════════════════════════════════"),
   writeln(""),
   normal_text("CONTROL TEXT ADVENTURE PROLOG ADAPTION BY SANDY MACDONALD 52534948"),
   writeln(""),
   normal_text("════════════════════════════════════════════════════════════"),
   writeln(""),
   writeln(""),
   normal_text("You are Jesse Faden."),
   writeln(""),
   normal_text("For years you told yourself you did not care about your brother. Dylan"),
   normal_text("ran toward the strange and unknowable, and you learned to run away."),
   normal_text("It was safer. Saner."),
   writeln(""),
   normal_text("Then the dreams started. His voice calling from somewhere vast."),
   normal_text("A building that did not exist on any map."),
   normal_text("A place called the Oldest House."),
   writeln(""),
   normal_text("You ignored it for as long as you could. But the dreams grew louder,"),
   normal_text("and Dylan's absence grew heavier, until ignoring became impossible."),
   writeln(""),
   normal_text("So you drove. You followed an address that should not exist."),
   normal_text("You arrive at a building that seems ordinary and utterly wrong."),
   normal_text("Tall. Featureless. Humming with a resonance you feel in your bones."),
   writeln(""),
   normal_text("The front doors wait. Inside, somewhere, Dylan is waiting too."),
   writeln(""),
   normal_text("And something else is waiting. Something that has been waiting."),
   writeln(""),
   normal_text("════════════════════════════════════════════════════════════"),
   writeln(""),
   writeln(""),
   buf_add(button, "Start Game"),
   writeln(""),
   writeln("").

%  Display the game state: map, intro text, tips, and current room details, called after prologue on first command (handle_command/1), plus the notes, thoughts items and npc occupents all the 'visual' info from my game to the webpage
show_game_state :-
   location(jesse, Room),
   show_map(Room),
   normal_text("You arrive at the Federal Bureau of Control."),
   normal_text("The building looms above you, humming with a strange, low resonance."),
   normal_text("Something pulls you toward the entrance."),
   description(Room, Desc),
   normal_text(Desc),
   writeln(""),
   tip_text("Tip: Look at the map above to see available locations. Try 'go north' to enter The Oldest House, or 'go east'/'go west' to explore other areas."),
   tip_text("Tip: try 'help' to list all available commands."),
   list_notes(Room),
   list_thoughts(Room),
   list_items(Room),
   list_occupants(Room).

%  Serve index.html from the working directory.
serve_index(Request) :-
 http_reply_file('index.html', [], Request).

%  POST /start — called once when the browser page loads.
handle_start(_Request) :-
   reset_game,
   retractall(prologue_shown),
   show_prologue_only,
   buf_flush(Lines),
   reply_json_dict(_{lines: Lines, ok: true}).

handle_command(Request) :-
    http_read_json_dict(Request, Dict),

    ( \+ prologue_shown
    -> show_game_state,
       assertz(prologue_shown)
    ; true
    ),

    Input = Dict.input,
    string_lower(Input, Lower),
    split_string(Lower, " ", " \t", Words0),
    maplist(clean_token_smart, Words0, Words),
    maplist(atom_string, Tokens, Words),

    ( Tokens \= [''] ->
        ( parse(Tokens, Command)
        -> ( game_over
           -> ( Command = restart
              -> reset_game,
                 retractall(prologue_shown),
                 buf_add(normal, "Game restarted!"),
                 show_prologue_only
              ; Command = quit
              -> true  % quit allowed when dead
              ; buf_add(normal, "You are dead. Type 'restart' to try again or 'quit' to exit.")
              )
           ;  dispatch(Command)
           )
        ;  buf_add(error, "I don't understand.")
        )
    ; true
    ),

    buf_flush(Lines),
    reply_json_dict(_{lines: Lines, ok: true}).

% render prologue text 
init_game_output :-
    show_prologue_only,
    show_game_state.

% restores all dynamic predicates to their initial state to reset the game on the server.
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
    retractall(cat_statue_placed),
    retractall(weapon_just_taken),
    retractall(shield_active),
    retractall(last_color(_)),
    retractall(last_buf_style(_)),
    assertz(last_color(default)),
    assertz(last_buf_style(none)),

    restart_game.

% server entry point, I'm hosting on port 8081 as the default port I was having problems with, also tell the end user a clickable link in the terminal to easily navigate to the web served game proper.
:- initialization(
    ( reset_game,
      http_server(http_dispatch, [port(8081)]),
      format("My Control Text Adventure Adaption Game Server is running at http://localhost:8081/~n"),
      thread_get_message(stop)
    ), main).