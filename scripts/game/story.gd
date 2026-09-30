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
		"The gate district. Every street is walled, every yard is locked, and the relay tower stands at the end of the avenue. Every part of this city has its own way in."},
	"east_yard": {"title": "The east yard", "text":
		"Somebody kept keys here, on hooks, labelled. Most hooks are empty. One is not."},
	"west_yard": {"title": "The west yard", "text":
		"A parked machine, a tarp, a box of cards for doors that no longer exist. One card is for a door that does."},
	"relay": {"title": "The relay", "text":
		"The card reads. The door slides. Inside: a lift going down into the dark, and a hum coming up from below. Your standing order says report to the relay. The relay is down there."},
	"agora": {"title": "The Agora", "text":
		"A market square. Stalls, wagons, crates of nothing. Everyone left in a hurry and the vines moved in. In the far corner a workshop, its shutter jammed shut."},
	"printer_shop": {"title": "The printer shop", "text":
		"A matter printer, taken apart on the floor. Its core still hums. With a nozzle it could print metal out of scrap: parts, panels, even a ramp."},
	"vault": {"title": "The Relay Vault", "text":
		"Cold air, humming cables, lamps that somebody kept burning. The relay is not a radio mast after all. It's a place."},
	"mirrors": {"title": "The mirror hall", "text":
		"Mirrors on stands, a dark lens in the far wall, and a lens in the west wall under a shaft to the sky. Light wants to get somewhere. Press E on a mirror to turn it."},
	"vault_lit": {"title": "Light", "text":
		"The beam finds the lens and the whole hall hums louder. At the far end, a heavy door grinds up."},
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
	"giant_close": {"title": "The eye", "text":
		"Its eye is the size of you. Behind the glass something is still faintly lit, counting down or counting up. It does not look at you."},
	"east_pocket": {"title": "The stream station", "text":
		"Somebody dragged a charger out here and hid it behind thorns. Full sun, running water, no visitors. A good place to stop being afraid."},
	"crooked_house": {"title": "The crooked house", "text":
		"Every wall leans a different way, like the house is trying to tiptoe off. Smoke from the chimney. Somebody lives here. You can hear them grumbling."},
	"zombie": {"title": "Angry Zombie", "text":
		"A zombie. A very grumpy one. He does not like visitors, and he REALLY does not like being poked."},
	"tiny": {"title": "The tiny curse", "text":
		"ZAP! Everything is suddenly enormous. You are tiny for two days. Tiny robots use less power... and fit through tiny holes."},
	"tiny_over": {"title": "Pop!", "text":
		"Back to full size. Maybe don't poke him next time. Or maybe do."},
	"sentry_won": {"title": "Sentry down", "text":
		"The sentry sits down with a clunk. Its big eye blinks... and turns green. Friendly now. Its shield plating clatters off beside it, and something is still wired in there: salvage it. The way to the city is open."},
	"sentry_down": {"title": "The Hill Sentry", "text":
		"It sits beside the path, humming to itself. When you roll past, its green eye follows you. It seems happier this way."},
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
