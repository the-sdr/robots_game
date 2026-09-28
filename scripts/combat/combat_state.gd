extends RefCounted

# The rules of a turn-based fight: no nodes, timers or input, so a test can
# play a whole fight in a loop. scripts/combat/combat.gd is the fight screen
# that drives it (keys, timing ring, animations). The numbers live in Catalog
# (moves, enemies, PLAYER_HEALTH) and Settings.tuning() (difficulty).
#
# A turn: the player picks a move; an attack has one timing press per hit
# ("perfect" x1.5, "good" x1, "miss" x miss_factor). Then the enemy attacks;
# one defence press per hit ("perfect" dodges, "good" halves). Guard moves
# soften the next blow and can hit back; a stun skips the enemy's next turn.

const PERFECT_BONUS := 1.5
const BLOCK_SHARE := 0.5

var tuning: Dictionary = {}
var enemy: Dictionary = {}
var tutorial := false
var player_hp := 0.0
var player_max := 0.0
var enemy_hp := 0.0
var enemy_max := 0.0
var turn := 0             # enemy attacks so far: picks the next one in order
var guard := 1.0          # share of the next enemy blow that lands
var counter := 0.0        # damage back when that blow is dodged or blocked
var evade := false        # the next enemy blow misses completely
var stunned := false      # the enemy loses its next turn
var outcome := ""         # "" while fighting, then "won" or "lost"

func start(enemy_def: Dictionary, difficulty: Dictionary, player_health: float) -> void:
	enemy = enemy_def
	tuning = difficulty
	tutorial = bool(enemy_def.get("tutorial", false))
	player_max = player_health
	player_hp = player_health
	enemy_max = roundf(float(enemy_def["health"]) * float(difficulty["enemy_health"]))
	enemy_hp = enemy_max
	turn = 0
	guard = 1.0
	counter = 0.0
	evade = false
	stunned = false
	outcome = ""

## How long the timing ring takes to close for something that takes `base` seconds at normal speed.
func ring_seconds(base: float) -> float:
	return base / float(tuning["ring_speed"])

## "perfect", "good" or "miss" for a press `offset` seconds from the beat (INF: no press).
func quality(offset: float) -> String:
	var off := absf(offset)
	if off <= float(tuning["perfect_window"]):
		return "perfect"
	if off <= float(tuning["good_window"]):
		return "good"
	return "miss"

## Defence: "perfect" = dodged (within defend_window of the blow), "good" =
## blocked (within twice that), "miss" = it lands.
func defence_quality(offset: float) -> String:
	var off := absf(offset)
	var window := float(tuning["defend_window"])
	if off <= window:
		return "perfect"
	if off <= window * 2.0:
		return "good"
	return "miss"

## Can this fight be lost? (Not the tutorial on Easy.)
func can_lose() -> bool:
	return not tutorial or bool(tuning["tutorial_knockout"])

func _attack_factor(q: String) -> float:
	match q:
		"perfect":
			return PERFECT_BONUS
		"good":
			return 1.0
	return float(tuning["miss_factor"])

## The player's move; `qualities` holds one timing result per hit of an attack.
## `weak`: the battery couldn't pay for it, so it lands at half power.
func player_move(move: Dictionary, qualities: Array, weak: bool = false) -> Dictionary:
	var result := {"damage": 0, "healed": 0}
	match String(move["kind"]):
		"attack":
			var total := 0.0
			for q in qualities:
				total += float(move["power"]) * _attack_factor(String(q))
			if weak:
				total *= 0.5
			var dealt := roundi(total)
			enemy_hp = maxf(enemy_hp - dealt, 0.0)
			result["damage"] = dealt
		"guard":
			guard = float(move.get("guard", 0.5))
			counter = float(move.get("counter", 0.0))
		"evade":
			evade = true
		"stun":
			stunned = true
		"repair":
			var before := player_hp
			player_hp = minf(player_hp + float(move.get("heal", 0.0)), player_max)
			result["healed"] = roundi(player_hp - before)
	if enemy_hp <= 0.0:
		outcome = "won"
	return result

## The attack the enemy will use this turn ({} when it is stunned and skips it).
func next_attack() -> Dictionary:
	if stunned:
		return {}
	var attacks: Array = enemy["attacks"]
	return attacks[turn % attacks.size()]

## Resolves the enemy's turn with one defence result per hit of its attack.
func enemy_move(qualities: Array) -> Dictionary:
	var result := {"damage": 0, "countered": 0, "skipped": false, "dodged": 0}
	if stunned:
		stunned = false
		turn += 1
		result["skipped"] = true
		return result
	var attack := next_attack()
	var total := 0.0
	var defended := false
	for i in int(attack.get("hits", 1)):
		var q: String = String(qualities[i]) if i < qualities.size() else "miss"
		var hit: float = float(attack["power"]) * float(tuning["enemy_damage"])
		if evade or q == "perfect":
			hit = 0.0
			defended = true
			result["dodged"] += 1
		elif q == "good":
			hit *= BLOCK_SHARE
			defended = true
		total += hit * guard
	var taken := roundi(total)
	player_hp -= taken
	if not can_lose():
		player_hp = maxf(player_hp, 1.0)
	result["damage"] = taken
	if defended and counter > 0.0:
		result["countered"] = roundi(counter)
		enemy_hp = maxf(enemy_hp - counter, 0.0)
	guard = 1.0
	counter = 0.0
	evade = false
	turn += 1
	if enemy_hp <= 0.0:
		outcome = "won"
	elif player_hp <= 0.0:
		player_hp = 0.0
		outcome = "lost"
	return result
