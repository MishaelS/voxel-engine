class_name ServerLists
extends RefCounted
## Who may do what on this computer's server (Net, the host or a dedicated
## server), kept next to each other in user://:
##   bans.cfg        [bans] tag = the name it was banned with (as before)
##   banned-ips.cfg  [ips] address = the name or reason
##   ops.cfg         [ops] name (lower case) = tag ("" until they join)
##   whitelist.cfg   [whitelist] name (lower case) = tag ("" until they join);
##                   [settings] enabled
## Names on the ops list and the whitelist are tied to the computer (its
## tag, PlayerProfile.tag_for_server) of whoever joins with them first
## (`enforce_tags`): someone else taking that name gets nothing.

const BANS_PATH := "user://bans.cfg"
const IPS_PATH := "user://banned-ips.cfg"
const OPS_PATH := "user://ops.cfg"
const WHITELIST_PATH := "user://whitelist.cfg"

var enforce_tags := true


static func _load(file: String) -> ConfigFile:
	var config := ConfigFile.new()
	config.load(file)
	return config


static func _keys(file: String, section: String) -> PackedStringArray:
	var config := _load(file)
	return config.get_section_keys(section) if config.has_section(section) else PackedStringArray()


# --- Bans ------------------------------------------------------------------------------

func is_banned(tag: String) -> bool:
	return _load(BANS_PATH).has_section_key("bans", tag)


func ban(tag: String, player_name: String) -> void:
	var config := _load(BANS_PATH)
	config.set_value("bans", tag, player_name)
	config.save(BANS_PATH)


## Lifts a ban by the start of the tag or the name. Returns the name or "".
func pardon(tag_or_name: String) -> String:
	var config := _load(BANS_PATH)
	if not config.has_section("bans"):
		return ""
	var wanted := tag_or_name.strip_edges().trim_prefix("#").to_lower()
	for tag: String in config.get_section_keys("bans"):
		var banned_name := str(config.get_value("bans", tag))
		if wanted != "" and (tag.begins_with(wanted) or banned_name.to_lower() == wanted):
			config.erase_section_key("bans", tag)
			config.save(BANS_PATH)
			return banned_name
	return ""


func is_ip_banned(address: String) -> bool:
	return address != "" and _load(IPS_PATH).has_section_key("ips", _ip_key(address))


func ban_ip(address: String, reason: String) -> void:
	var config := _load(IPS_PATH)
	config.set_value("ips", _ip_key(address), reason)
	config.save(IPS_PATH)


func pardon_ip(address: String) -> bool:
	var config := _load(IPS_PATH)
	if not config.has_section_key("ips", _ip_key(address)):
		return false
	config.erase_section_key("ips", _ip_key(address))
	config.save(IPS_PATH)
	return true


func banned_ips() -> PackedStringArray:
	var result := PackedStringArray()
	for key in _keys(IPS_PATH, "ips"):
		result.append(key.replace("_", ":"))
	return result


## ConfigFile keys can't hold ":" (IPv6 addresses).
static func _ip_key(address: String) -> String:
	return address.strip_edges().to_lower().replace(":", "_")


# --- Ops and the whitelist -----------------------------------------------------------------

## Whether `player_name` (with `tag`) is on a list; a name not tied to a
## computer yet is tied to this one now.
func _on_list(file: String, section: String, player_name: String, tag: String) -> bool:
	var config := _load(file)
	var key := player_name.to_lower()
	if not config.has_section(section):
		return false
	if config.has_section_key(section, key):
		var bound := str(config.get_value(section, key, ""))
		if bound == "" and tag != "":
			config.set_value(section, key, tag)
			config.save(file)
			return true
		return bound == tag or not enforce_tags
	for other: String in config.get_section_keys(section):
		if str(config.get_value(section, other)) == tag and tag != "":
			return true # (the same computer with a new name)
	return false


func _add(file: String, section: String, player_name: String, tag: String) -> void:
	var config := _load(file)
	config.set_value(section, player_name.to_lower(), tag)
	config.save(file)


func _remove(file: String, section: String, player_name: String) -> bool:
	var config := _load(file)
	var key := player_name.strip_edges().to_lower()
	if not config.has_section_key(section, key):
		return false
	config.erase_section_key(section, key)
	config.save(file)
	return true


func is_op(player_name: String, tag: String) -> bool:
	return _on_list(OPS_PATH, "ops", player_name, tag)


func op(player_name: String, tag: String) -> void:
	_add(OPS_PATH, "ops", player_name, tag)


func deop(player_name: String) -> bool:
	return _remove(OPS_PATH, "ops", player_name)


func ops() -> PackedStringArray:
	return _keys(OPS_PATH, "ops")


func whitelist_enabled() -> bool:
	return bool(_load(WHITELIST_PATH).get_value("settings", "enabled", false))


func set_whitelist_enabled(on: bool) -> void:
	var config := _load(WHITELIST_PATH)
	config.set_value("settings", "enabled", on)
	config.save(WHITELIST_PATH)


func is_whitelisted(player_name: String, tag: String) -> bool:
	return _on_list(WHITELIST_PATH, "whitelist", player_name, tag)


func whitelist_add(player_name: String, tag: String) -> void:
	_add(WHITELIST_PATH, "whitelist", player_name, tag)


func whitelist_remove(player_name: String) -> bool:
	return _remove(WHITELIST_PATH, "whitelist", player_name)


func whitelist() -> PackedStringArray:
	return _keys(WHITELIST_PATH, "whitelist")
