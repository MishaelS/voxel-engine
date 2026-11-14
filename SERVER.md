# Running a server

There are three ways to play with friends, from the quickest to the biggest:

1. **Open to LAN** (pause menu): your world is open while you play in it.
   *Allow Internet Access* opens the port on the router (UPnP) and gives an
   invite code.
2. **Create Server** (Multiplayer screen): choose a world, maybe a password
   and internet access; the game starts a server in the background on your
   computer and joins it. Friends join it like any server (*My Server* /
   *Invite Friends* show its code and addresses). Leaving asks whether to
   stop it (the world is saved); quitting the game stops it. Its settings
   are in `server/server.properties` in the game folder (the world, the
   password and internet access are set by the screen; the rest can be
   changed there).
3. **A dedicated server** (this page): the game without a window, a camera
   or sound, keeping one world running for everyone, day and night,
   whether you play or not.

Players join a server with **Multiplayer > Direct Connect** (or Add Server):
its address, `address:port`, a domain name (`myserver.duckdns.org`) or an
invite code.

## Starting

**A released game** (the zip from the releases): next to the game are

| File | System | How |
| --- | --- | --- |
| `start-server.bat` | Windows | double-click |
| `start-server.command` | macOS | double-click (the first time: right-click > Open) |
| `start-server.sh` | Linux | `./start-server.sh` |
| `server.properties.example` | all | every setting explained |

The server's window is its console: type commands there, `stop` saves and
stops (on macOS and Linux also Ctrl+C or closing the window). Copy the
whole folder anywhere: the server is portable.

**Where the settings are:** `server.properties` next to the game (on macOS:
next to the `.app`), else in the folder the server was started from, else
in the game folder (`user://`). The first start makes it next to the game
(or in the game folder when that folder can't be written to), with every
setting and what it does. `--config FILE` names another one.

**From the project** (Godot 4.5 installed):

```sh
tools/run.sh --server                                 # server.properties of the current folder, or the game folder's
tools/run.sh --server --port 25570 --world survival2
cd ~/voxel-server && /path/to/voxel-engine/tools/run.sh --server
```

Directly:

```sh
godot --headless --path /path/to/voxel-engine -- --server [--port N] [--world NAME] [--config FILE]
"./Voxel Engine Bedrock Edition.x86_64" --headless --server [--port N] [--world NAME] [--config FILE]
```

- `--port`, `--world` - override `server-port` and `world-name`.
- `tools/run.sh` finds Godot as `$GODOT`, else the editor in /Applications,
  else `godot` on the PATH.
- The game's native library (faster world generation) is built for macOS,
  Windows and Linux (see BUILDING.md); without it the server still works,
  only slower.

Worlds are kept where the game keeps them (`saves/` in the game folder:
`~/.local/share/Godot/app_userdata/Voxel Engine` on Linux,
`~/Library/Application Support/Godot/app_userdata/Voxel Engine` on macOS,
`%APPDATA%\Godot\app_userdata\Voxel Engine` on Windows). A world made in the
game can be named in `world-name` (its folder's name).

The log is written to the console and to `logs/latest.log` next to
`server.properties` (the one before is kept with its date, the last 20).
On start it says where players connect: the LAN addresses, and
`Players connect to: <address>` when `public-address` is set (or when UPnP
opened the router's ports).

## The console

What you type is run as a server command (with or without `/`), with every
right:

| Command | What it does |
| --- | --- |
| `help` | all commands |
| `list`, `players` | who is in (with their tags and addresses) |
| `say <text>` | a message to everyone |
| `kick <player> [reason]` | sends a player away |
| `ban <player>`, `pardon <name or tag>` | bans a player's computer (its tag) |
| `ban-ip <player or address>`, `pardon-ip <address>` | bans an address |
| `op <player>`, `deop <player>` | operators may cheat and run these commands from the chat |
| `whitelist add/remove <name>`, `whitelist list`, `whitelist on/off` | who may join |
| `save-all` | saves now |
| `stop` | saves the world and the players, sends everyone away, exits |
| `tp`, `gamemode`, `give`, `time`, `weather`, `gamerule`, `kill`, `summon`, `setblock`, `fill`... | the game's commands, on any player (`@a`, names) |

**Ctrl+C**, `kill <pid>` or `systemctl stop` stop the server cleanly through
`tools/run.sh --server`, `start-server.sh` or `start-server.command` (they
turn the signal into `stop`). Godot can't catch signals itself, so a server
started without them only stops cleanly with `stop` (on Windows: type `stop`;
closing the window loses the last minutes).
`invite` shows the address players connect to.

## server.properties

| Key | Default | What it does |
| --- | --- | --- |
| `server-port` | 25565 | UDP port of the game; the server list's ping uses this port + 1 |
| `server-ip` | (all) | the address to listen on |
| `world-name` | world | the world's folder in `saves/` (made when missing) |
| `seed` | (random) | seed of a new world (a number, or text) |
| `world-type` | default | a new world's type: default, tall, floating, island |
| `bonus-chest` | false | a chest of starting things by the spawn of a new world |
| `gamemode` | survival | survival or creative |
| `difficulty` | normal | peaceful, easy, normal, hard |
| `max-players` | 20 | players at most (1-100) |
| `motd` | A Voxel Engine Server | the message in the server list |
| `password` | (none) | joining needs it; players type it once when joining. It never goes over the network (a hash with a one-time number does) |
| `white-list` | false | only players on the whitelist (and ops) may join |
| `enforce-tags` | true | names on the whitelist and the ops list are tied to the computer that first joined with them |
| `view-distance` | 12 | columns around a player the server sends changed land for |
| `simulation-distance` | 5 | columns around each player kept loaded and ticking |
| `spawn-protection` | 16 | blocks around the spawn only ops may change (0: off) |
| `idle-timeout` | 0 | minutes before an idle player is kicked (0: never) |
| `pvp` | true | players can hurt each other |
| `autosave-minutes` | 5 | minutes between saves |
| `upnp` | false | open the ports on a home router by UPnP |
| `public-address` | (none) | the address players connect to from the internet: an IP or a domain name (`myserver.duckdns.org`, with `:port` when not 25565); printed on start, given by `/invite` instead of the router's address |
| `lan-broadcast` | false | show the server in the Multiplayer list on the same network |
| `max-connections-per-ip` | 3 | connections at most from one address |
| `spawn-radius` | 3 | columns kept loaded around the spawn while nobody plays |

Restart the server after changing it (`whitelist on/off` changes `white-list`
by itself). Keep the file private: it holds the password.

Next to the game's settings (`user://`) are `ops.cfg`, `whitelist.cfg`,
`bans.cfg` and `banned-ips.cfg` (and `server.cfg` with the server's salt:
players' tags depend on it, keep it to keep the bans).

## Opening it to the internet

1. **Ports:** UDP **25565** (the game) and UDP **25566** (the server list's
   ping) - or your `server-port` and the one after it.
2. **Firewall** on the server:
   - Ubuntu/Debian: `sudo ufw allow 25565:25566/udp`
   - firewalld: `sudo firewall-cmd --permanent --add-port=25565-25566/udp && sudo firewall-cmd --reload`
   - Windows: `netsh advfirewall firewall add rule name="Voxel Engine" dir=in action=allow protocol=UDP localport=25565-25566`
   - a cloud server: also allow them in the provider's security group / firewall.
3. **At home:** forward both ports on the router to the server's computer
   (or `upnp=true`). Behind CGNAT (the router has no public address) this
   can't work: use a VPS, or a VPN like ZeroTier / Radmin VPN.
4. Players connect to the public address (`203.0.113.5` or `play.example.com:25570`).
5. **A name instead of the number:** a home address changes now and then.
   A free dynamic DNS name (e.g. [DuckDNS](https://www.duckdns.org): make a
   name, run its updater on the server's computer) always points at it, or
   use your own domain (an A record). Put the name in `public-address`; the
   server prints `Players connect to: myserver.duckdns.org` and `/invite`
   gives it. The game looks names up itself (Direct Connect, the server
   list).

## Keeping it running

**screen / tmux:**

```sh
tmux new -s voxel 'cd ~/voxel-server && ./start-server.sh'
# later: tmux attach -t voxel   (detach: Ctrl+B then D)
```

**systemd** (`/etc/systemd/system/voxel-server.service`):

```ini
[Unit]
Description=Voxel Engine server
After=network-online.target

[Service]
User=voxel
WorkingDirectory=/home/voxel/server
ExecStart=/home/voxel/server/start-server.sh
# SIGTERM to the script only: it says "stop" to the server, which saves.
# (From the project instead: ExecStart=/path/to/voxel-engine/tools/run.sh --server)
KillMode=mixed
TimeoutStopSec=60
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

```sh
sudo systemctl daemon-reload && sudo systemctl enable --now voxel-server
journalctl -u voxel-server -f        # the log
```

Under systemd nobody types in the console: use an op's chat, or stop and
start the service.

## What the server checks

Everything goes through the server: players don't reach each other
directly, and what a client sends is checked before the world sees it.

- Joining: the version, a name of 3-16 letters (A-Z), digits and `_` (the
  game spells other letters that way by itself), bans by computer and by
  address, the password, the whitelist, max players; at most 8 joins waiting
  at once, 3 connections and 8 tries in 30 seconds from one address; a join
  that doesn't introduce itself in 10 seconds is dropped.
- Movement: faster than walking, flying (creative) or riding allows is sent
  back to the last good place; teleports and respawns go through the server.
- Building and using: within reach (6 blocks, 8 in creative) of where the
  server sees the player, in loaded land only, outside the spawn protection;
  survival can't place or break what only the world makes (bedrock,
  spawners).
- Game modes and cheats are the server's: `/gamemode` and `/tp` run there,
  cheat commands only for ops.
- Chests and furnaces: two players can't take the same stack.
- Floods (chat, edits, column requests...) are refused; impossible data
  (unknown blocks and items, absurd sizes, positions outside the world)
  adds up to a kick quickly.

### Lag is not cheating

A bad connection is never punished like a cheat:

- Movement may arrive late and in bursts: what a player may cover grows
  with the time since its last message (up to 5 seconds of it at once), so
  the messages a lag spike held back pass. Going further than that only
  sends the player back (and is logged as `[movement]`); a kick (E302)
  needs more than 30 such corrections in a minute, over at least 15
  seconds: a speed hack does that, lag doesn't. Nobody is banned
  automatically.
- Flood limits are token buckets with three times the limit saved up, so a
  burst after a stall isn't spam; refused messages are logged as `[flood]`,
  and only sending about three times the limit for ten seconds is a kick
  (E303).
- Out of reach (the server sees the player a moment late) is refused and
  logged, never counted towards a kick.
- A connection is dropped only after ENet's timeout: no answer for 10 to
  30 seconds (both sides). A player the server hasn't heard from for 3
  seconds (or that loses many packets) is told "Your connection is
  unstable" and the log says `[net] ... connection problems`. The player
  sees *Bad connection* in the top right corner while nothing comes from
  the server for 1.5 seconds or the round trip is over 500 ms.

### Error codes

When a join is refused or a game ends, the player sees why and a code
(the Disconnected screen), in their own language; the server's log shows
the same code with the English text. Tell the code when asking for help.

| Code | Meaning |
| --- | --- |
| E101 | Connection lost |
| E102 | Timed out: the server stopped answering |
| E103 | The server was stopped |
| E104 | The host left the game (Open to LAN) |
| E201 | Wrong password |
| E202 | Not on the whitelist |
| E203 | Banned (the computer or the address) |
| E204 | The server is full |
| E205 | Version mismatch: the server has X, you have Y |
| E206 | The name isn't 3-16 of A-Z, 0-9, _ |
| E207 | The server needs a password (the game asks for it) |
| E208 | Too many connections from one address |
| E209 | The server is busy (too many joins at once) |
| E210 | The host is not in a world |
| E211 | The join didn't introduce itself (a different or broken game) |
| E300 | Kicked by an operator |
| E301 | Kicked by an operator, with the reason |
| E302 | Kicked for moving too fast (a long run of corrections) |
| E303 | Kicked for spamming |
| E304 | Kicked for sending bad data |
| E305 | Idle for too long (`idle-timeout`) |
| E401 | Can't resolve the address (the name doesn't exist) |
| E402 | Can't reach the server (nothing answers at that address and port) |
| E403 | The invite code has a typo |
| E404 | No address |
| E405 | Can't connect to the address |
| E501 | Create Server: the server didn't start |
| E502 | Create Server: the port is taken by another program |

The codes and their texts are in `scripts/net/net_errors.gd`; translations
are lines in `assets/lang/*.lang` like every other text of the game.

Limits: inventories are still each player's own, so a modified game can give
itself items in survival (the server refuses only impossible ones); falling
damage and hovering aren't checked; a flood at the network level needs a
firewall or the provider's protection.
