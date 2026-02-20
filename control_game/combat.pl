:- module(combat, [combat_turn/2, start_combat/1]).
:- dynamic health/2.

start_combat(NPC) :-
    combat_turn(jesse, NPC).

combat_turn(jesse, Enemy) :-
    writeln("You attack."),
    apply_damage(Enemy, 12),
    enemy_retaliate(Enemy).

apply_damage(Target, Dmg) :-
    health(Target, HP),
    NewHP is max(0, HP - Dmg),
    retract(health(Target, HP)),
    assert(health(Target, NewHP)),
    format("~w now has ~w HP.~n", [Target, NewHP]).

enemy_retaliate(Enemy) :-
    health(Enemy, HP),
    (   HP =< 0
    ->  format("~w falls silent.~n", [Enemy])
    ;   writeln("It strikes back."),
        apply_damage(jesse, 8)
    ).
