:- use_module('./parser.pl').
:- use_module('./world.pl').
:- use_module('./map.pl').
:- use_module('./infection.pl').
:- use_module('./dialogue.pl').
:- use_module('./combat.pl').
:- use_module('./objects.pl').

:- module(world, [
    location/2, health/2, resonance/2, has/2,
    describe_here/0, move/2
]).

:- dynamic location/2.
:- dynamic health/2.
:- dynamic resonance/2.
:- dynamic has/2.

location(jesse, lobby).
health(jesse, 100).
resonance(jesse, 30).
has(jesse, none).

describe_here :-
    location(jesse, Room),
    description(Room, Desc),
    writeln(Desc),
    list_occupants(Room).

list_occupants(Room) :-
    findall(N, (npc(N), location(N, Room)), NPCs),
    findall(E, (enemy(E), location(E, Room)), Enemies),
    (NPCs \= [] -> format("You see: ~w~n", [NPCs]) ; true),
    (Enemies \= [] -> format("Hostiles present: ~w~n", [Enemies]) ; true).

move(Actor, Dir) :-
    location(Actor, Room),
    (   connected(Room, Next, Dir)
    ->  retract(location(Actor, Room)),
        assert(location(Actor, Next)),
        describe_here
    ;   writeln("You can't go that way.")
    ).
