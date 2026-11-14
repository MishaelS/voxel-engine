class_name NetErrors
extends RefCounted
## Why a network game ended or a join was refused, as a short code the
## player can report ("E302") and a message in their own language.
##
## The server sends only the code and its arguments (Net._refused), never a
## finished English sentence, so each client shows the message in the
## language it plays in; the server's console and log show the code with
## the English text.
##
## Messages are written in English here and translated like every other
## text of the game (Lang): each one is a line "English=Translation" in
## assets/lang/<language>.lang (%s keep their places), so another language
## is one more .lang file with these lines. Codes never change meaning:
## a new reason gets a new code.
##
##   E1xx  the connection itself (lost, timed out, the server closed)
##   E2xx  joining refused (password, whitelist, bans, full, version, name)
##   E3xx  sent away while playing (kicks)
##   E4xx  this computer couldn't reach the server (address, network)
##   E5xx  starting a server from the game (Create Server)

const CONNECTION_LOST := 101
const TIMED_OUT := 102
const SERVER_CLOSED := 103
const HOST_LEFT := 104
const WRONG_PASSWORD := 201
const NOT_WHITELISTED := 202
const BANNED := 203
const SERVER_FULL := 204
const VERSION_MISMATCH := 205
const BAD_NAME := 206
const PASSWORD_NEEDED := 207
const TOO_MANY_CONNECTIONS := 208
const SERVER_BUSY := 209
const HOST_NOT_IN_WORLD := 210
const HANDSHAKE_FAILED := 211
const KICKED := 300
const KICKED_REASON := 301
const KICKED_MOVING := 302
const KICKED_SPAM := 303
const KICKED_BAD_DATA := 304
const KICKED_IDLE := 305
const CANT_RESOLVE := 401
const CANT_REACH := 402
const INVITE_TYPO := 403
const NO_ADDRESS := 404
const CANT_CONNECT := 405
const SERVER_DIDNT_START := 501
const PORT_TAKEN := 502

## Code -> the English message (%s: the arguments, in order).
const MESSAGES := {
	CONNECTION_LOST: "Connection lost",
	TIMED_OUT: "Timed out: the server stopped answering",
	SERVER_CLOSED: "The server was stopped",
	HOST_LEFT: "The host left the game",
	WRONG_PASSWORD: "Wrong password",
	NOT_WHITELISTED: "You are not white-listed on this server",
	BANNED: "You are banned from this server",
	SERVER_FULL: "The server is full",
	VERSION_MISMATCH: "Version mismatch: the server has %s, you have %s",
	BAD_NAME: "Your name can only have 3-16 letters (A-Z), digits and _",
	PASSWORD_NEEDED: "This server needs a password",
	TOO_MANY_CONNECTIONS: "Too many connections from your address",
	SERVER_BUSY: "The server is busy, try again in a moment",
	HOST_NOT_IN_WORLD: "The host is not in a world",
	HANDSHAKE_FAILED: "Could not join: the server didn't understand the game",
	KICKED: "Kicked by an operator",
	KICKED_REASON: "Kicked by an operator: %s",
	KICKED_MOVING: "Kicked for moving too fast",
	KICKED_SPAM: "Kicked for spamming",
	KICKED_BAD_DATA: "Kicked for sending bad data",
	KICKED_IDLE: "You have been idle for too long",
	CANT_RESOLVE: "Can't resolve the address %s",
	CANT_REACH: "Can't reach server",
	INVITE_TYPO: "This invite code has a typo",
	NO_ADDRESS: "No address",
	CANT_CONNECT: "Can't connect to %s",
	SERVER_DIDNT_START: "The server didn't start: %s",
	PORT_TAKEN: "Port %s is taken by another program",
}
## Arguments at most (a changed server can't send a flood of them).
const MAX_ARGS := 4
const ARG_LENGTH := 100


## "E205" for 205.
static func label(code: int) -> String:
	return "E%03d" % code


## The message of `code` in the player's language, with `args` filled in.
static func text(code: int, args: PackedStringArray = PackedStringArray()) -> String:
	return _fill(Lang.t(MESSAGES.get(code, "Disconnected")), args)


## The English message with the code, for logs: "E302 Kicked for moving too fast".
static func log_text(code: int, args: PackedStringArray = PackedStringArray()) -> String:
	return "%s %s" % [label(code), _fill(MESSAGES.get(code, "Disconnected"), args)]


## Arguments from the network made safe: a few short lines of plain text.
static func clean_args(args: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	for i in mini(args.size(), MAX_ARGS):
		result.append(NetGuard.clean_text(args[i], ARG_LENGTH))
	return result


## Whether the player can fix it by typing a password (the password screen).
static func wants_password(code: int) -> bool:
	return code == PASSWORD_NEEDED or code == WRONG_PASSWORD


static func _fill(message: String, args: PackedStringArray) -> String:
	var wanted := message.count("%s")
	if wanted == 0:
		return message
	var values: Array = []
	for i in wanted:
		values.append(args[i] if i < args.size() else "?")
	return message % values
