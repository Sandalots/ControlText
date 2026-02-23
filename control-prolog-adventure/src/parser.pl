:- dynamic parse/2.

parse([go, Dir], go(Dir)).
parse([move, Dir], go(Dir)).
parse([walk, Dir], go(Dir)).

parse([look], look).
parse([look, at, Obj], look_at(Obj)).

parse([take, Obj], take(Obj)).
parse([pick, up, Obj], take(Obj)).

parse([talk, NPC], talk(NPC)).
parse([attack, Enemy], attack(Enemy)).

parse([quit], quit).
parse([help], help).

parse([enter], go(enter)).
parse([go, inside], go(enter)).
parse([go, in], go(enter)).