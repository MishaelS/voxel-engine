class_name InviteCode
extends RefCounted
## An invite code: the host's internet address (IPv4 and port) as a short
## code that's easy to read out or type, like "VE-7Q3M-1KD9": the 4 bytes of
## the address and a byte of checksum in Crockford's base32 (no I, L, O, U:
## when typed they're read as 1, 1, 0 and nothing looks alike). A port
## other than the default adds 4 letters ("VE-XXXX-XXXX-XXXX") with a longer
## checksum. The checksum catches typos, so a mistyped code says so instead
## of connecting to a stranger's address.
## Not secret: anyone with the code can find the address (hence the warning
## to share it only with friends).

const PREFIX := "VE"
const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
## Bits of checksum: short codes (default port) and long ones.
const SHORT_CHECK := 8
const LONG_CHECK := 12


## The code for an IPv4 address and port ("" for anything else).
static func encode(ip: String, port: int = Net.PORT) -> String:
	var bytes := _ip_bytes(ip)
	if bytes.is_empty() or port <= 0 or port > 65535:
		return ""
	var value := 0
	for b in bytes:
		value = (value << 8) | b
	var bits := 32
	var check_bits := SHORT_CHECK
	if port != Net.PORT:
		value = (value << 16) | port
		bits = 48
		check_bits = LONG_CHECK
	value = (value << check_bits) | _checksum(value, check_bits)
	bits += check_bits
	var digits := ""
	for i in range(bits / 5 - 1, -1, -1):
		digits += ALPHABET[(value >> (i * 5)) & 31]
	var groups := PackedStringArray([PREFIX])
	for i in range(0, digits.length(), 4):
		groups.append(digits.substr(i, 4))
	return "-".join(groups)


## The address ("ip:port") in a code, "" when it isn't one (or has a typo).
## Case, dashes and spaces don't matter; the "VE" in front is needed (so a
## server's name is never read as a code).
static func decode(code: String) -> String:
	var text := code.to_upper().replace("-", "").replace(" ", "").strip_edges()
	if not text.begins_with(PREFIX):
		return ""
	text = text.substr(PREFIX.length())
	var check_bits := SHORT_CHECK if text.length() == 8 else LONG_CHECK if text.length() == 12 else 0
	if check_bits == 0:
		return ""
	var value := 0
	for c in text:
		var digit := ALPHABET.find(c.replace("O", "0").replace("I", "1").replace("L", "1"))
		if digit < 0:
			return ""
		value = (value << 5) | digit
	var check := value & ((1 << check_bits) - 1)
	value >>= check_bits
	if _checksum(value, check_bits) != check:
		return ""
	var port := Net.PORT
	if check_bits == LONG_CHECK:
		port = value & 0xFFFF
		value >>= 16
		if port == 0:
			return ""
	return "%d.%d.%d.%d:%d" % [(value >> 24) & 255, (value >> 16) & 255, (value >> 8) & 255, value & 255, port]


## Does this look like a code (whether or not it's a valid one)? For telling
## the player "that code has a typo" instead of "can't resolve hostname".
static func looks_like_code(text: String) -> bool:
	var plain := text.strip_edges().to_upper()
	return plain.begins_with(PREFIX + "-") or (plain.begins_with(PREFIX) and plain.count("-") >= 2)


## A typed address or code as an address to connect to: a code's address,
## anything else as it was typed.
static func to_address(text: String) -> String:
	var address := decode(text)
	return address if address != "" else text.strip_edges()


## Is an IPv4 address one that can't be reached from the internet (local
## networks, the providers' shared CGNAT range 100.64/10, loopback,
## link-local)?
static func is_private_ip(ip: String) -> bool:
	var b := _ip_bytes(ip)
	if b.is_empty():
		return false
	return b[0] == 10 or b[0] == 127 or b[0] == 0 \
		or (b[0] == 172 and b[1] >= 16 and b[1] < 32) \
		or (b[0] == 192 and b[1] == 168) \
		or (b[0] == 169 and b[1] == 254) \
		or (b[0] == 100 and b[1] >= 64 and b[1] < 128)


## This computer's addresses on local networks (and VPNs like Radmin VPN
## or ZeroTier, which are private ranges too): what local friends connect to.
static func lan_addresses() -> Array[String]:
	var result: Array[String] = []
	for ip in IP.get_local_addresses():
		if is_private_ip(ip) and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			result.append(ip)
	# Radmin VPN's 26.x addresses aren't private, but are only reachable over it.
	for ip in IP.get_local_addresses():
		if ip.begins_with("26.") and _ip_bytes(ip).size() == 4:
			result.append(ip)
	return result


static func _ip_bytes(ip: String) -> PackedByteArray:
	var parts := ip.strip_edges().split(".")
	var result := PackedByteArray()
	if parts.size() != 4:
		return result
	for part in parts:
		if not part.is_valid_int() or int(part) < 0 or int(part) > 255:
			return PackedByteArray()
		result.append(int(part))
	return result


## FNV-1a over the value's bytes, folded to `bits` bits.
static func _checksum(value: int, bits: int) -> int:
	var hash := 2166136261
	for i in range(7, -1, -1):
		hash = ((hash ^ ((value >> (i * 8)) & 255)) * 16777619) & 0xFFFFFFFF
	return (hash ^ (hash >> bits) ^ (hash >> (bits * 2))) & ((1 << bits) - 1)
