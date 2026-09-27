extends Node

# Autoload "Story": placeholder narrative beats, shown once each per save.
# Greek mythology is the touchstone (owner). Surface goal: report to the city
# relay. Rewrite freely: only the ids matter to the code.
# Beats fire from StoryTrigger areas, from Interactables (Inspect), or from
# code (world.gd on waking and on the first dock).

const BEATS := {
	"wake": {"title": "Boot sequence", "text":
		"Power restored. Last shutdown: [record damaged]. Standing order still in memory: report to the relay in the city. First: get out of this room."},
	"door": {"title": "The door", "text":
		"It was locked from the outside. Whoever did that meant to come back."},
	"copy": {"title": "Hearth", "text":
		"The station copies you while you charge. If you stop out there, you start again here, from the copy. That is not the same as not stopping."},
	"gate": {"title": "The garden", "text":
		"Everything green has had a long time to itself. The path north is the only one that is still a path."},
	"fork": {"title": "Two ways", "text":
		"Old wood to the west, pines to the east. Both go north eventually. The battery decides how much eventually you can afford."},
	"giant": {"title": "Talos", "text":
		"A machine the size of a house, face down in the stream. Its beacon still points at the sky. Whatever it guarded is gone, and it never noticed."},
	"under_giant": {"title": "Inside the giant", "text":
		"A hollow under its chest. Someone slept here once: a blanket, a tin, a name scratched into the plate. The name is not yours."},
	"ruin": {"title": "The ruin", "text":
		"A doorway with no building. A stair to nowhere. Older than the machines, older than whoever locked your door."},
	"clearing": {"title": "The dry clearing", "text":
		"Open sky. From here both the giant and the hill can be seen. The sun is a resource here. Remember that."},
	"exit": {"title": "The trees part", "text":
		"Onto the hill. The forest lets you go without a word."},
	"crest": {"title": "The city", "text":
		"There it is. Nothing moves. The relay tower still stands at its centre. Report in anyway. That is the order."},
	"hub": {"title": "Delphi", "text":
		"The city's gate is shut, and its locks are bigger than your smasher. Every district has its own way in. Find them."},
	"brambles": {"title": "Thorns", "text":
		"The stream leaves the forest under a wall of thorn. Something sharp and spinning would clear it."},
	"spring": {"title": "The spring", "text":
		"Water still runs out of a concrete pipe. Somebody built that. Somebody kept it working, for a while."},
	"hollow_tree": {"title": "The hollow", "text":
		"Inside a twisted trunk, a part wrapped in cloth. Left for someone. Taken by you."},
	"pine_end": {"title": "Deep pines", "text":
		"The needles swallow sound. You would not hear anything coming. Nothing comes."},
	"garden_nook": {"title": "The greenhouse", "text":
		"Behind the house, a frame with no glass. The plants inside outgrew it and kept going."},
	"ruin_far": {"title": "The hatch", "text":
		"Beyond the ruin, a sealed hatch in the ground. Warm to the touch. Not today."},
	"shutdown": {"title": "Power lost", "text":
		"Systems shutting down. The last copy of you waits at the charger."},
}

## Shows a beat once per save. Returns true if it played.
func play(beat_id: String) -> bool:
	if Game.beat_seen(beat_id) or not BEATS.has(beat_id):
		return false
	Game.mark_beat(beat_id)
	var beat: Dictionary = BEATS[beat_id]
	get_tree().call_group("hud", "show_message", beat["title"], beat["text"])
	return true
