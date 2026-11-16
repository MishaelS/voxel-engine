class_name Holidays
extends RefCounted
## Days the game dresses up for, by the computer's own date like the modern
## game's: New Year chests (terrain.png's present tiles: Blocks._chest) and,
## around Halloween, pumpkins on zombies', skeletons' and creepers' heads
## (Mob.equip). `-- --date=MM-DD` on the command line plays another day.


static func _today() -> Dictionary:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--date="):
			var parts := arg.trim_prefix("--date=").split("-")
			if parts.size() == 2:
				return {"month": parts[0].to_int(), "day": parts[1].to_int()}
	return Time.get_date_dict_from_system()


## December 24 .. January 7.
static func new_year() -> bool:
	var d := _today()
	return (d.month == 12 and d.day >= 24) or (d.month == 1 and d.day <= 7)


## October 20 .. November 3, like the modern game's.
static func halloween() -> bool:
	var d := _today()
	return (d.month == 10 and d.day >= 20) or (d.month == 11 and d.day <= 3)
