/* ============================================
      CONTROL — TEXT ADVENTURE  ·  WEB SERVER
      server.pl

      This module wraps the single-file game
      (control.pl) in a lightweight HTTP server
      so it can be played in a browser.

   ── HOW IT WORKS ────────────────────────────
      1. All output predicates are defined HERE
         before control.pl is loaded.  Because
         Prolog resolves predicates at call-time,
         these definitions shadow the terminal
         versions that control.pl wraps inside
         its :- if(\+ current_module(server)) guard.
      2. Instead of writing to stdout, every
         output call pushes a tagged text record
         onto output_buffer/1.
      3. At the end of each HTTP request,
         buf_flush/1 reverses the buffer into
         an ordered list and sends it as JSON:
           { lines: [{text, style}, …], ok: true }
      4. index.html receives the JSON and renders
         each line with its matching CSS class
         (normal, highlight, map, tip, speak, note,
         spacer).

   ── ENDPOINTS ───────────────────────────────
      GET  /             → redirect to /index.html
      GET  /index.html   → serve the HTML UI
      POST /start        → reset + render opening
      POST /command      → parse + dispatch input

   ── PORT ────────────────────────────────────
      Listens on localhost:8081.
      Change the port number in initialization/2
      at the bottom of this file if needed.

   ── RUNNING ─────────────────────────────────
      swipl server.pl
      Then open http://localhost:8081/ in a browser.
   ============================================ */

:- module(server, []).

:- use_module(library(http/thread_httpd)). % multi-threaded HTTP server engine
:- use_module(library(http/http_dispatch)). % declarative route dispatch table
:- use_module(library(http/http_json)).     % http_read_json_dict/2, reply_json_dict/1
:- use_module(library(http/http_files)).    % http_reply_file/3 for static files

/* ============================================
      OUTPUT BUFFER
      Game output is collected into a list rather
      than written directly to stdout, so it can
      be serialised as JSON at the end of each
      HTTP request.

      output_buffer/1 holds the list in reverse
      order (newest item first) for O(1) prepend;
      buf_flush/1 reverses it before returning.

      Each entry is a SWI-Prolog dict:
        _{text: "…", style: <style_atom>}
      where style is one of:
        normal | highlight | map | tip |
        speak  | note      | spacer
      (These match the CSS classes in index.html.)

      last_buf_style/1 tracks the style of the
      most recently buffered line so that buf_add/2
      can insert a blank spacer entry whenever the
      style changes, providing visual separation
      between differently-coloured output blocks
      without requiring explicit blank lines in
      the game logic.
   ============================================ */

:- dynamic output_buffer/1.  % output_buffer(ReversedList)
:- dynamic last_buf_style/1. % last_buf_style(StyleAtom | none)
:- dynamic prologue_shown/0.  % prologue_shown — flag for tracking prologue display

% Initial facts — reset by buf_flush/1 and reset_game/0.
output_buffer([]).
last_buf_style(none).

%% buf_add(+Style, +Text)
%  Append a styled text line to the output buffer.
%  Automatically inserts a spacer entry when the
%  style changes, so output blocks are visually
%  separated in the browser without needing
%  explicit blank lines in game logic.
%
%  Special styles (web-only):
%    button — Renders as a clickable button in the browser.
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

%% buf_flush(-Lines)
%  Drain the buffer: return Lines as an ordered list
%  (oldest first), reset the buffer to empty, and
%  reset the style tracker to `none`.
%  Called at the end of handle_start/1 and
%  handle_command/1 before replying with JSON.
buf_flush(Lines) :-
    retract(output_buffer(Buf)),
    assertz(output_buffer([])),
    retractall(last_buf_style(_)),
    assertz(last_buf_style(none)),
    reverse(Buf, Lines).

/* ============================================
      OUTPUT PREDICATES  (web versions)
      These definitions are loaded BEFORE
      control.pl, so they take precedence over
      the terminal (ansi_format) versions that
      control.pl defines inside its :- if guard.

      Each predicate maps to a CSS class:
        normal_text    → .normal    (green)
        highlight_text → .highlight (yellow)
        map_text       → .map       (cyan monospace)
        tip_text       → .tip       (magenta bold)
        note_text      → .note      (red italic)
        speak/2        → .speak     (red italic)

      color_ln/2 bridges any remaining direct
      calls to the old ANSI color_ln/2 API,
      mapping: red→note, yellow→highlight,
      cyan→map, anything else→normal.

      space_if_color_changed/0 is a no-op here
      because buf_add/2 already inserts spacers
      automatically on style change.

      writeln/1 is overridden so that empty-string
      calls (used as explicit blank lines in
      list_notes/1, list_thoughts/1, etc.) are
      converted to spacer entries rather than
      silently discarded.  A spacer is only added
      if the buffer is non-empty (Last \= none),
      preventing a leading spacer at the top of a
      response.  The style tracker is reset to
      `none` after inserting a spacer so that two
      consecutive writeln("") calls don't produce
      a double gap.
   ============================================ */

% last_color/1 is kept as a stub — buf_add tracks style instead.
:- dynamic last_color/1.
last_color(default).

normal_text(Text)    :- buf_add(normal, Text).
highlight_text(Text) :- buf_add(highlight, Text).
map_text(Text)       :- buf_add(map, Text).
tip_text(Text)       :- buf_add(tip, Text).
note_text(Text)      :- buf_add(note, Text).
speak(_, Text)       :- buf_add(speak, Text). % NPC identity ignored; style is uniform

% Map the legacy ANSI color_ln/2 API to the nearest web style.
color_ln(red, Text)    :- buf_add(note, Text).
color_ln(yellow, Text) :- buf_add(highlight, Text).
color_ln(cyan, Text)   :- buf_add(map, Text).
color_ln(_, Text)      :- buf_add(normal, Text).

% space_if_color_changed is handled automatically by buf_add style tracking.
space_if_color_changed.

%% writeln(+Text)  [override]
%  Empty strings (used as explicit blank-line separators in game code)
%  become spacer entries in the buffer; consecutive empty strings only
%  produce one spacer.  Non-empty terms are converted to strings and
%  buffered as normal text.
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

/* ============================================
      LOAD GAME MODULE
      control.pl is consulted AFTER the output
      predicates above are defined.  Because
      control.pl's output predicates are wrapped
      in :- if(\+ current_module(server)), they
      are skipped here and the server versions
      above are used instead for all output.
   ============================================ */
:- [control].

/* ============================================
      HTTP ROUTES
      Declared with http_handler/3 directives;
      http_dispatch/1 routes each request to the
      matching predicate based on path + method.

        GET  /             → redirect to /index.html
        GET  /index.html   → serve static UI file
        POST /start        → start or restart game
        POST /command      → process one player turn
   ============================================ */

:- http_handler(root(.),            http_redirect(moved, '/index.html'), []).
:- http_handler(root('index.html'), serve_index,   []).
:- http_handler(root(start),        handle_start,  [method(post)]).
:- http_handler(root(command),      handle_command,[method(post)]).

%% show_prologue_only/0
%  Display only the prologue (Jesse's backstory) to the buffer.
%  Called on initial page load (handle_start/1) and on restart.
show_prologue_only :-
    writeln(""),
    writeln(""),
    writeln(""),
    normal_text("════════════════════════════════════════════════════════════"),
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

%% show_game_state/0
%  Display the game state: map, intro text, tips, and current room details.
%  Called after prologue on first command (handle_command/1).
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
    list_notes(Room),
    list_thoughts(Room),
    list_items(Room),
    list_occupants(Room).

%% serve_index(+Request)
%  Serve index.html from the working directory.
%  SWI's http_reply_file/3 handles ETag caching
%  and Content-Type automatically.
serve_index(Request) :-
    http_reply_file('index.html', [], Request).

%% handle_start(+Request)
%  POST /start — called once when the browser page loads.
%  Resets all dynamic game state to initial values via
%  reset_game/0, shows the prologue, and sets a flag to
%  display the game state on the first command.
handle_start(_Request) :-
    reset_game,
    retractall(prologue_shown),
    show_prologue_only,
    buf_flush(Lines),
    reply_json_dict(_{lines: Lines, ok: true}).

%% handle_command(+Request)
%  POST /command — called for every player turn.
%  On first call (prologue_shown not asserted): show the game state,
%  then assert prologue_shown so future commands skip this step.
%  Pipeline:
%    1. Read JSON body: { input: "<player text>" }
%    2. If prologue_shown not yet asserted: render game state and set flag
%    3. Lowercase and split on whitespace.
%    4. Clean each token (strip punctuation, preserve
%       alphanumeric codes like bureau47).
%    5. Convert string tokens to atoms for parse/2.
%    6. Skip empty input (e.g. player pressed Enter twice).
%    7. parse/2 → if Command = restart, call reset_game
%       and re-render the opening; otherwise dispatch/1.
%    8. If parse/2 fails, buffer the error message.
%    9. Flush buffer to JSON and reply.
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
        -> ( Command = restart
           -> reset_game,
              retractall(prologue_shown),
              buf_add(normal, "Game restarted!"),
              show_prologue_only
           ;  dispatch(Command)
           )
        ;  buf_add(error, "I don't understand.")
        )
    ; true
    ),
    buf_flush(Lines),
    reply_json_dict(_{lines: Lines, ok: true}).

%% init_game_output/0
%  Legacy: render opening scene (used for backward compatibility).
%  For web server: kept for use when restart command is called
%  without needing prologue_shown flag handling.
init_game_output :-
    show_prologue_only,
    show_game_state.

%% reset_game/0
%  Full game reset for the web server context.
%  Differs from the standalone restart_game/0 in that
%  it also clears the server-specific dynamic state
%  (last_color, last_buf_style) and re-seeds them to
%  their initial values before delegating to
%  restart_game/0 (defined in control.pl), which
%  re-asserts all entity locations, health, and items.
%  Called by handle_start/1 and by handle_command/1
%  when the player issues a 'restart' command.
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
    retractall(last_color(_)),         % server-side colour tracker stub
    retractall(last_buf_style(_)),     % output buffer style tracker
    assertz(last_color(default)),
    assertz(last_buf_style(none)),
    restart_game.                      % re-asserts all game facts (control.pl)

/* ============================================
      ENTRY POINT
      initialization/2 with goal `main` fires
      when the file is loaded with:
        swipl server.pl
      Steps:
        1. reset_game   — ensure a clean slate.
        2. http_server  — start the HTTP listener
                          on port 8081 using the
                          http_dispatch/1 router,
                          which reads the route
                          directives declared above.
        3. thread_get_message(stop) — park the main
                          thread indefinitely so the
                          server keeps running.
                          Send the atom `stop` to
                          this thread to shut down
                          gracefully.
   ============================================ */
:- initialization(
    ( reset_game,
      http_server(http_dispatch, [port(8081)]),
      format("My Control Text Adventure Adaption Game Server is running at http://localhost:8081/~n"),
      thread_get_message(stop)
    ), main).
