# Running a dedicated server

A dedicated server is the game without a window, a camera or sound: it keeps
one world running for everyone who joins, day and night, whether you play
or not. Players join it like any other game: **Multiplayer > Direct Connect**
(or Add Server) with its address, `address:port`, or an invite code.

## Starting

From the project's folder (Godot 4.5 installed):

```sh
mkdir ~/voxel-server && cd ~/voxel-server
/path/to/voxel-engine/tools/run_server.sh               # server.properties here
/path/to/voxel-engine/tools/run_server.sh --port 25570 --world survival2
```

On Windows: `tools\run_server.bat` (type `stop` to save and stop).

Directly with Godot, or with an exported game:

```sh
godot --headless --path /path/to/voxel-engine -- --server [--port N] [--world NAME] [--config FILE]
"./Voxel Engine" --headless --server --config /srv/voxel/server.properties
```

- `--config` - the settings file (default: `server.properties` in the folder
  `run_server.sh` was started from; without the script `user://server.properties`).
  It is made with every setting and its explanation on the first start.
- `--port`, `--world` - override `server-port` and `world-name`.
- Godot is found as `$GODOT`, else `godot` on the PATH.
- The game's native library is built for macOS only; on Linux and Windows
  the server works without it (world generation is slower), or build
  `native/` for that system (`native/build.sh`, CMake).

Worlds are kept where the game keeps them (`saves/` in the game folder:
`~/.local/share/Godot/app_userdata/Voxel Engine` on Linux,
`~/Library/Application Support/Godot/app_userdata/Voxel Engine` on macOS,
`%APPDATA%\Godot\app_userdata\Voxel Engine` on Windows). A world made in the
game can be copied there and named in `world-name`.

The log is written to the console and to `logs/latest.log` next to
`server.properties` (the one before is kept with its date, the last 20).

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
`run_server.sh` (it turns the signal into `stop`). Godot can't catch signals
itself, so a server started without the script only stops cleanly with `stop`.

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

## Keeping it running

**screen / tmux:**

```sh
tmux new -s voxel 'cd ~/voxel-server && /path/to/voxel-engine/tools/run_server.sh'
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
Environment=GODOT=/usr/local/bin/godot
ExecStart=/home/voxel/voxel-engine/tools/run_server.sh
# SIGTERM to the script only: it says "stop" to the server, which saves.
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
  at once, 3 connections and 5 tries in 30 seconds from one address;
  silent connections are dropped after 15 seconds.
- Movement: faster than walking, flying (creative) or riding allows is sent
  back; teleports and respawns go through the server.
- Building and using: within reach (6 blocks, 8 in creative) of where the
  server sees the player, in loaded land only, outside the spawn protection;
  survival can't place or break what only the world makes (bedrock,
  spawners).
- Game modes and cheats are the server's: `/gamemode` and `/tp` run there,
  cheat commands only for ops.
- Chests and furnaces: two players can't take the same stack.
- Floods (chat, edits, column requests...) are refused, and too many or too
  much bad data is a kick.

Limits: inventories are still each player's own, so a modified game can give
itself items in survival (the server refuses only impossible ones); falling
damage and hovering aren't checked; a flood at the network level needs a
firewall or the provider's protection.
