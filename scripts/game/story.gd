extends Node

# Autoload "Story": narrative beats, shown once each per save.
# Two games, two voices (owner, 2026-10-02): every beat has a Silly text (short,
# jokey, read aloud to a six-year-old) and a Serious one (gritty: rust, loss,
# and the city as the goal). A beat with only one mode's text plays only in
# that mode (the Angry Zombie and his curse are Silly's; the old robot is
# Serious'). Greek mythology is the touchstone. Rewrite freely: only the ids
# matter to the code. {interact} and friends become that action's button
# (Glyphs), so no key name is ever typed into the text.
# Beats fire from StoryTrigger areas, from Interactables (Inspect), or from
# code (world.gd on waking and on the first dock).

const BEATS := {
	"wake": {
		"silly": ["Beep boop!", "Power ON! You are a little robot with one job: get to the big city and say hello to the relay tower. But first... get out of this room!"],
		"serious": ["Boot sequence", "Power restored. Last shutdown: [record damaged]. One standing order survived: report to the relay in the city, north of here. Nobody has answered it in a very long time. First: get out of this room."],
	},
	"door": {
		"silly": ["Smash!", "The door is open! Somebody locked it from the outside. Rude!"],
		"serious": ["The door", "It was locked from the outside. Whoever did that meant to come back. They never did."],
	},
	"copy": {
		"silly": ["Backup!", "While you charge, the station makes a copy of you. If your battery runs out, the copy wakes up here. Ta-da!"],
		"serious": ["Hearth", "The station copies you while you charge. If you stop out there, you start again here, from the copy. That is not the same as not stopping."],
	},
	"gate": {
		"silly": ["The garden", "Trees, trees, everywhere trees! Only one path goes north. Follow it!"],
		"serious": ["The garden", "Everything green has had a long time to itself. The path north is the only one that is still a path."],
	},
	"fork": {
		"silly": ["Left or right?", "Old trees one way, pointy pine trees the other. Both go north. Pick one!"],
		"serious": ["Two ways", "Old wood to the west, pines to the east. Both go north eventually. The battery decides how much eventually you can afford."],
	},
	"giant": {
		"silly": ["A GIANT robot!", "A robot as big as a house, napping face-down in the stream. Shhh. Don't wake him. (He won't wake up.)"],
		"serious": ["Talos", "A machine the size of a house, face down in the stream. Its beacon still points at the sky. Whatever it guarded is gone, and it never noticed."],
	},
	"under_giant": {
		"silly": ["Secret den", "A cosy hideout under the giant! A blanket, a tin, and a name scratched on the metal. Not your name. Whose is it?"],
		"serious": ["Inside the giant", "A hollow under its chest. Someone slept here once: a blanket, a tin, a name scratched into the plate. The name is not yours."],
	},
	"ruin": {
		"silly": ["Wonky ruins", "A door with no house. Stairs to nowhere. Somebody forgot to finish building!"],
		"serious": ["The ruin", "A doorway with no building. A stair to nowhere. Older than the machines, older than whoever locked your door."],
	},
	"clearing": {
		"silly": ["Sunny spot", "No trees! Lots of sun! Robots love sun. Sun = power. Remember that!"],
		"serious": ["The dry clearing", "Open sky. From here both the giant and the hill can be seen. The sun is a resource here. Remember that."],
	},
	"exit": {
		"silly": ["Out of the woods!", "You made it out of the forest! Up the hill you go."],
		"serious": ["The trees part", "Onto the hill. The forest lets you go without a word."],
	},
	"crest": {
		"silly": ["THE CITY!", "Look! A whole city! And the tall relay tower in the middle. That's where you're going!"],
		"serious": ["The city", "There it is. Nothing moves. The relay tower still stands at its centre. Report in anyway. That is the order."],
	},
	"hub": {
		"silly": ["Delphi", "Walls and gates everywhere! Every street has its own lock. Time to find some keys."],
		"serious": ["Delphi", "The gate district. Every street is walled, every yard is locked, and the relay tower stands at the end of the avenue. Every part of this city has its own way in."],
	},
	"east_yard": {
		"silly": ["Key hooks", "Lots of hooks for keys. Almost all empty. Almost!"],
		"serious": ["The east yard", "Somebody kept keys here, on hooks, labelled. Most hooks are empty. One is not."],
	},
	"west_yard": {
		"silly": ["Card box", "A big box of door cards. Most are for doors that fell down. One still works!"],
		"serious": ["The west yard", "A parked machine, a tarp, a box of cards for doors that no longer exist. One card is for a door that does."],
	},
	"relay": {
		"silly": ["Going down!", "The door slides open. A lift goes down, down, down into the dark. Something down there is humming a song."],
		"serious": ["The relay", "The card reads. The door slides. Inside: a lift going down into the dark, and a hum coming up from below. Your standing order says report to the relay. The relay is down there."],
	},
	"agora": {
		"silly": ["The market", "A market with nobody shopping! The vines did all the shopping. In the corner: a workshop that's stuck shut."],
		"serious": ["The Agora", "A market square. Stalls, wagons, crates of nothing. Everyone left in a hurry and the vines moved in. In the far corner a workshop, its shutter jammed shut."],
	},
	"printer_shop": {
		"silly": ["The printer", "A magic metal printer, in bits on the floor. Fix it and it can print things out of junk!"],
		"serious": ["The printer shop", "A matter printer, taken apart on the floor. Its core still hums. With a nozzle it could print metal out of scrap: parts, panels, even a ramp."],
	},
	"vault": {
		"silly": ["The vault", "Cold air, humming cables and lamps that are still on. The relay isn't a tower after all. It's a secret place!"],
		"serious": ["The Relay Vault", "Cold air, humming cables, lamps that somebody kept burning. The relay is not a radio mast after all. It's a place."],
	},
	"mirrors": {
		"silly": ["Mirror room", "Mirrors! And a beam of sunlight. Bounce the light into the dark lens. Press {interact} on a mirror to turn it."],
		"serious": ["The mirror hall", "Mirrors on stands, a dark lens in the far wall, and a lens in the west wall under a shaft to the sky. Light wants to get somewhere. Press {interact} on a mirror to turn it."],
	},
	"vault_lit": {
		"silly": ["You did it!", "The light hits the lens and the whole room goes HMMMM. A big door slides open!"],
		"serious": ["Light", "The beam finds the lens and the whole hall hums louder. At the far end, a heavy door grinds up."],
	},
	"brambles": {
		"silly": ["Ouch, thorns!", "A big prickly wall of thorns. Something sharp and spinny would chop through it."],
		"serious": ["Thorns", "The stream leaves the forest under a wall of thorn. Something sharp and spinning would clear it."],
	},
	"spring": {
		"silly": ["Splash!", "Water pouring out of a big pipe. Somebody built this a long time ago."],
		"serious": ["The spring", "Water still runs out of a concrete pipe. Somebody built that. Somebody kept it working, for a while."],
	},
	"hollow_tree": {
		"silly": ["Tree hidey-hole", "Something wrapped up inside a tree! A present? It's a robot part. Yours now!"],
		"serious": ["The hollow", "Inside a twisted trunk, a part wrapped in cloth. Left for someone. Taken by you."],
	},
	"pine_end": {
		"silly": ["Quiet pines", "So quiet here! You can hear yourself beep."],
		"serious": ["Deep pines", "The needles swallow sound. You would not hear anything coming. Nothing comes."],
	},
	"garden_nook": {
		"silly": ["The greenhouse", "A greenhouse with no glass! The plants grew right out of the top."],
		"serious": ["The greenhouse", "Behind the house, a frame with no glass. The plants inside outgrew it and kept going."],
	},
	"ruin_far": {
		"silly": ["A hatch!", "A secret door in the ground. It's warm! Not today though."],
		"serious": ["The hatch", "Beyond the ruin, a sealed hatch in the ground. Warm to the touch. Not today."],
	},
	"giant_close": {
		"silly": ["Big eye", "The giant's eye is as big as you! Something inside is still blinking. Hello?"],
		"serious": ["The eye", "Its eye is the size of you. Behind the glass something is still faintly lit, counting down or counting up. It does not look at you."],
	},
	"east_pocket": {
		"silly": ["Secret charger!", "Somebody hid a charger behind the thorns! Sunny, splashy and safe."],
		"serious": ["The stream station", "Somebody dragged a charger out here and hid it behind thorns. Full sun, running water, no visitors. A good place to stop being afraid."],
	},
	"crooked_house": {
		"silly": ["The crooked house", "Every wall is wonky! Smoke from the chimney. Somebody lives here. Somebody GRUMPY."],
		"serious": ["The crooked house", "Every wall leans a different way, as if the house is trying to tiptoe off. A candle burns inside. Something has kept it lit."],
	},
	"zombie": {
		"silly": ["Angry Zombie", "A zombie. A very grumpy one. He does not like visitors, and he REALLY does not like being poked."],
	},
	"tiny": {
		"silly": ["The tiny curse", "ZAP! Everything is suddenly enormous. You are tiny for two days. Tiny robots use less power... and fit through tiny holes."],
	},
	"tiny_over": {
		"silly": ["Pop!", "Back to full size. Maybe don't poke him next time. Or maybe do."],
	},
	"old_robot": {
		"serious": ["The old robot", "A robot slumped in the corner. Same treads, same arms, same head as yours, under a coat of rust. One lens still flickers. Its battery reads empty."],
	},
	"old_robot_wakes": {
		"serious": ["Unit four", "The old robot drinks the charge and lifts its head. \"You are a Model Four. So was I. They told me to wait here for her. I waited until the house leaned and the trees came in.\" It reaches into the wardrobe and hands you something it kept all this time. \"The city is north, past the hill. Take this. Don't wait like I did.\""],
	},
	"sentry_won": {
		"silly": ["You win!", "The sentry sits down with a BONK. Its big eye blinks... and turns green. Friends now! Its shield plate fell off. Cut it or zap it for parts!"],
		"serious": ["Sentry down", "The sentry sits down hard. Its eye flickers, then settles to green. It has stopped guarding. Its shield plating lies beside it with parts still wired inside: salvage it. The way to the city is open."],
	},
	"sentry_down": {
		"silly": ["Sentry buddy", "Your sentry friend is sitting by the path, humming a happy song."],
		"serious": ["The Hill Sentry", "It sits beside the path, humming to itself. When you roll past, its green eye follows you. It seems lighter this way."],
	},
	"shutdown": {
		"silly": ["Uh oh, no power!", "Bzzzt... sleepy time. You'll wake up at your last charger."],
		"serious": ["Power lost", "Systems shutting down. The last copy of you waits at the charger."],
	},
}

## This mode's {title, text} for a beat; empty if the beat isn't in this mode.
func beat(beat_id: String) -> Dictionary:
	var b: Dictionary = BEATS.get(beat_id, {})
	if not b.has(Game.mode):
		return {}
	var pair: Array = b[Game.mode]
	return {"title": pair[0], "text": _buttons(String(pair[1]))}

## Shows a beat once per save. Returns true if it played.
func play(beat_id: String) -> bool:
	var b := beat(beat_id)
	if b.is_empty() or Game.beat_seen(beat_id):
		return false
	Game.mark_beat(beat_id)
	get_tree().call_group("hud", "show_message", b["title"], b["text"])
	return true

## {action} -> that action's button name, from Glyphs (keyboard or pad).
func _buttons(text: String) -> String:
	while text.contains("{"):
		var start := text.find("{")
		var stop := text.find("}", start)
		if stop < 0:
			break
		text = text.substr(0, start) + Glyphs.label(text.substr(start + 1, stop - start - 1)) + text.substr(stop + 1)
	return text
