class_name ArgumentType
extends RefCounted
## Base class of command argument types. A type parses its text into a
## value and suggests completions; commands only declare which types they
## use, so parsing and suggestion code is written once per type.

## How many space-separated tokens the argument takes (3 for x y z);
## GREEDY takes the rest of the input (messages).
const GREEDY := -1

var token_count := 1


## Parses the argument text. Returns {"value": parsed} or {"error": message}.
func parse(_text: String, _source: CommandSource) -> Dictionary:
	return {"error": "Not implemented"}


## Completions for the partially typed argument text.
func suggest(_partial: String, _source: CommandSource) -> PackedStringArray:
	return PackedStringArray()


static func ok(value: Variant) -> Dictionary:
	return {"value": value}


static func fail(message: String) -> Dictionary:
	return {"error": message}


## Helper for suggest(): candidates that start with the partial text.
static func filter_prefix(candidates: PackedStringArray, partial: String) -> PackedStringArray:
	var result := PackedStringArray()
	var lower := partial.to_lower()
	for candidate in candidates:
		if candidate.to_lower().begins_with(lower):
			result.append(candidate)
	return result
