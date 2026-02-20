combat_turn(jesse, Enemy, Result).
combat_turn(Enemy, jesse, Result).

health(jesse, 100).
resonance(jesse, 30).   % used for abilities
has(jesse, service_weapon).

enemy(hiss_guard).
health(hiss_guard, 40).
state(hiss_guard, infected).

weapon_mode(grip).     % single‑shot
weapon_mode(shatter).  % close‑range burst
weapon_mode(spin).     % rapid fire

damage(grip, 12).
damage(shatter, 20).
damage(spin, 6).

perform(jesse, switch(Mode)) :-
    weapon_mode(Mode),
    retract(current_mode(_)),
    assert(current_mode(Mode)).

perform(jesse, attack(Enemy)) :-
    current_mode(Mode),
    damage(Mode, Dmg),
    apply_damage(Enemy, Dmg).

apply_damage(Target, Dmg) :-
    health(Target, HP),
    NewHP is max(0, HP - Dmg),
    retract(health(Target, HP)),
    assert(health(Target, NewHP)).

enemy_action(Enemy, attack) :-
    state(Enemy, infected).

enemy_action(Enemy, charge) :-
    state(Enemy, overrun).

enemy_action(Enemy, stagger) :-
    state(Enemy, tainted).

enemy_attack(Enemy) :-
    enemy_action(Enemy, attack),
    apply_damage(jesse, 8).

enemy_attack(Enemy) :-
    enemy_action(Enemy, charge),
    apply_damage(jesse, 15).

enemy_attack(Enemy) :-
    enemy_action(Enemy, stagger).

perform(jesse, launch(Enemy)) :-
    resonance(jesse, R),
    R >= 5,
    apply_damage(Enemy, 18),
    NewR is R - 5,
    retract(resonance(jesse, R)),
    assert(resonance(jesse, NewR)).

perform(jesse, shield) :-
    resonance(jesse, R),
    R >= 4,
    retract(resonance(jesse, R)),
    assert(resonance(jesse, R - 4)),
    assert(temp_shield(10)).   % absorbs next 10 damage

apply_damage(jesse, Dmg) :-
    temp_shield(S),
    S > 0,
    Absorb is min(S, Dmg),
    NewS is S - Absorb,
    retract(temp_shield(S)),
    assert(temp_shield(NewS)),
    Remaining is Dmg - Absorb,
    (Remaining > 0 -> apply_damage(jesse, Remaining) ; true), !.

combat_turn(jesse, Enemy, continue) :-
    perform(jesse, Action),
    (health(Enemy, 0) -> Result = victory ; enemy_attack(Enemy)).

combat_turn(Enemy, jesse, defeat) :-
    health(jesse, 0), !.

state(Room, infected) :-
    location(Enemy, Room),
    escalate_enemy(Enemy).

escalate_enemy(Enemy) :-
    state(Enemy, infected),
    retract(state(Enemy, infected)),
    assert(state(Enemy, overrun)).
