# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versioning follows [Semantic Versioning](https://semver.org/).

Sections:
- **Added** - new features.
- **Changed** - changes to existing behavior.
- **Fixed** - bug fixes.
- **Removed** - removed features.

## [Unreleased]

### Changed
- The Island world type is a small island now (SmallIslandsGenerator): a sandy beach round a low, uneven hill with a forest on it (the main island's radius 44-60 blocks, stretched and turned by the seed, its shore going in and out in bays and capes, the beach wide here and narrow there), a deep sea all around (36 blocks) and, by the seed, up to 3 little islets with a tree or two some way off. One biome (forest) everywhere; under the islands Beta's caves, ores and dungeons, under the open sea only ores. It was Beta's whole land with all its biomes cut off 260 blocks from the middle. Island worlds made before keep that generator (no seams).
- Faster: the fire, lava and water textures' simulations run in C++ (NativeTextureFx; about 0.8 ms of every frame before); random ticks take a quarter of the chunks a tick with four times the tries each (a block is ticked as often as before, gathering the chunks was most of their cost) and grass ticks that can change nothing (air above, no open dirt in reach, all inside one chunk) are left out in C++; the chunk meshing queue passes over columns that can't be meshed yet before looking their chunks up. Scripts take about 1.3-1.7 ms a frame (2.3-2.6 before), a tick's random ticks 1.4 ms (2.75, with peaks of 7.5).

### Fixed
- The player could appear on top of a tree: leaves no longer count as ground for the spawn point.

## [0.0.30] - 2026-11-18

### Added
- Simulation Distance in Video Settings (4-16 chunks, 8 by default), like the modern game's: around every player only that far the world lives - creatures, dropped items, flowing water and lava, fire, redstone, furnaces, random ticks (they reached 8 columns before); beyond, out to the render distance, the world is only drawn and waits just as it is, going on from there when a player comes near. Monsters out there still go away like Beta's when over 128 blocks from every player.
- Creatures far and idle are seen to less often, like Paper's entity activation range: over 32 blocks from every player, standing on the ground with nothing going on (no target, not hurt, burning, swimming, panicking, in love, tame or riding), a creature is ticked once a second instead of 20 times; anything that happens to it wakes it at once. Creatures' ticks cost about a fifth of what they did.

### Changed
- The game is called "Voxel Engine Godot Edition" (it is made with Godot) instead of "Voxel Engine Bedrock Edition": window title, debug screen, a new drawn title logo (VOXEL ENGINE in cracked stone blocks over a GODOT EDITION plate), a splash text, exported games and their server scripts, the docs. Worlds and settings stay in the same folder, and players keep their ids on servers.
- Faster, on macOS especially: the game draws with Godot's Mobile renderer there (made for tiled GPUs like Apple's M chips), a steady 60 frames a second (the window's limit) at render distance 12 where the Forward+ renderer gave 54-57 with stutters while flying; it looks the same. Windows and Linux keep Forward+.
- Less work each frame: creatures out of the camera's sight are not posed or lit (their animation was the biggest part of a frame's script time); creatures' round shadows are made again only when they would look different; the compass and clock icons are drawn again only when the needle or dial turns a pixel and sent to the graphics card only when they changed (the whole item atlas went 20 times a second), and the compass no longer searches the spawn point anew 20 times a second; the chunk meshing queue is sorted with one check per column instead of per chunk. Scripts take about 4 ms a frame standing instead of 7.5.
- Signs look like Beta 1.7.3's (TileEntitySignRenderer): the text is smaller - a font pixel 1/90 block, so 15 letters just fill the board - with a line every 10 font pixels (the lines touched and ran over the board's edges); a sign post's board stands higher, its top above the block (to 1.08), on a darker post (the log's side) instead of planks; a wall sign hangs a little off the wall.
- The "Achievement get!" plate is drawn in pixels like the modern game's toasts: a black edge with rounded corners, a grey frame 2 pixels wide and dark grey inside (it was a see-through dark box with a thin bluish line).

### Fixed
- Sunrise and sunset were pink: the orange glow was mixed into the blue sky in linear light, as a flat band. They are now Beta 1.7.3's (WorldProvider.calcSunriseSunsetColors and RenderGlobal's fan): a warm orange glow lying flat along the horizon on the sun's side (90 degrees each way, about 18 up and down), its color and strength rising and falling with the dawn, blended in plain colors like Beta's; the fog toward the sun takes the same color the way Beta's does (EntityRenderer.updateFogColor).
- The debug screen named the renderer from the project settings instead of the one running (Forward+ while macOS uses Mobile).

## [0.0.29] - 2026-11-17

### Changed
- Squids' tentacles open like Beta 1.7.3's ModelSquid: each one away from the body's middle, a fan of eight at a stroke, straight down again between strokes (they all swung the same way). The body no longer spins about its own length on every push (it turned about half round each time); it still leans and turns toward where it swims.
- Fire looks like Beta 1.7.3's (RenderBlocks.renderBlockFire): instead of two crossed pictures, eight sheets 1.4 blocks high - four crossing in the middle, leaning out toward the top, and four round the sides leaning in - with both fire tiles (31 inside, 47 outside), full bright.
- Burning creatures look like Beta 1.7.3's (Render.renderEntityOnFire): instead of a fire block stretched over them, sheets of fire turned to the camera, the first 1.4 x the creature's width square, each next one 0.45 of that higher, 10% narrower and a little farther back, until they reach over its head; the two fire tiles by turns, every other pair mirrored.

### Fixed
- A mob skin of another size than 64 x 32 (the new 330 x 165 squid.png) made the mob invisible: the models took the picture's own size for the layout their texture places count in. Skins are now laid out 64 wide (32 or 64 high by their shape) whatever their size, so bigger, finer pictures work too.

## [0.0.28] - 2026-11-16

### Changed
- Chests open without the lid animation again: a click opens the window at once with the chest's opening sound and the closing sound when it closes, like Beta 1.7.3's. A chest with a solid block on top still doesn't open.
- Tall grass, ferns and dead bushes stand a little off the middle of their block like the modern game's (each place its own, the same every time): up to a quarter block sideways, grass and ferns also sunk up to 0.2 into the ground. Their hit box stays where it was.
- Statistics' Blocks and Items pages look like Beta 1.7.3's GuiStats (with our textures): every block or item there is, in their order, in a slot frame (gui/slot.png), every other row grey, with its numbers under three columns headed by slot.png's pictures - Blocks: crafted, used, mined; Items: broken, crafted, used - "-" where a column means nothing for it (no recipe, doesn't wear out, unbreakable), "0" where it just hasn't happened, its name in a tooltip; a click on a heading sorts by it (again: the other way, with slot.png's arrow). General, Blocks and Items are 100 pixels wide in a row with Done under them on the right, like Beta's.

### Fixed
- Squids jerked as they swam and kept to one depth: they now swim like Beta 1.7.3's EntitySquid, number for number - a stroke cycle opening and closing the tentacles, a push at 3/4 of it that dies away, a new way 1 time in 50 ticks (up and down too, -0.1..0.1 against 0.2 sideways), no gravity or drag in water, the body turning toward its way and leaning along it a tenth a tick, spinning about itself while it pushes, drawn between ticks like RenderSquid; out of water they fall flapping and tip onto their side.

### Added
- Fence gates like the modern game's: crafted from 4 sticks and 2 planks (sticks at the sides, planks in the middle), they join fences on both ends and open with a click or redstone; opened from the other side they swing away from the player. Open, they let players and creatures through but no blocks into their place.
- An open trapdoor over a ladder on the same wall can be climbed like the ladder, as in the modern game.
- Holidays by the computer's date, like the modern game's: from December 24 to January 7 chests are presents (terrain.png's own tiles: a single chest red, a large one blue; from the game's terrain.png when a texture pack has none); from October 20 to November 3 a zombie, skeleton or creeper spawns with a carved pumpkin on its head 1 time in 4 (a jack o'lantern 1 in 10 of those), which never drops. `-- --date=MM-DD` on the command line plays another day.
- Debug hitboxes like the modern game's F3+B (debug builds only): a white box around every creature, cart, boat, arrow, dropped item and network player nearby, a red rectangle at a creature's eye height and a blue line 2 blocks long where its head looks; the chat says when they are shown or hidden. As in the modern game, F3 alone now turns the debug screen on or off when it is let go, so F3+B doesn't.
- World pictures in Select World (ours, like the modern game's): each world shows a 64 x 64 picture on the left, the middle of the view taken a few seconds after a new world first shows and again every time the player leaves it (without the HUD, the hand or the menus), kept as icon.png in the world's folder; worlds without one show missing_world_icon.png.
- Rename World like Beta 1.7.3's: Select World has Rename next to Delete (both half wide, Cancel wide, like Beta's buttons); it opens a field with the world's name ready to type over, Rename (not while empty) and Cancel. Only the name in the world's level file changes, everything else in it and its folder stay.
- A quiver (ours; Beta's items.png had its picture but no item): crafted from 2 string, 2 paper and 4 leather (string down the left, paper over leather), it holds up to 128 arrows. Arrows held over it go in with a click (a right click: one), a right click with nothing held takes out a stack, a quiver held and right-clicked on arrows takes them in; its tooltip tells how many it holds and a blue bar shows how full it is. The bow shoots from it before loose arrows, arrows picked up go into it first.
- Charged creepers like Beta 1.7.3's: lightning striking near a creeper hurts and burns it like any creature and charges it (onStruckByLightning). It glows like Beta's RenderCreeper (armor/power.png on the model, 1 pixel out where Beta's was 2, the picture sliding 0.01 a tick, at half color, added to what is behind) and blows up with power 6 instead of 3 (in dirt about 600 blocks instead of 120; in stone hardly more, as in Beta). Saved, and seen by network players.
- Spider jockeys like Beta 1.7.3's (SpawnerAnimals.creatureSpecificInit): 1 naturally spawned spider in 100 comes with a skeleton riding it. The skeleton sits on its back like Beta's (the spider's height x 0.75 - 0.5 above its feet, legs forward), the spider walks after the player and the skeleton shoots from it; when the spider dies the skeleton gets off. Saved as one, seen by network players riding.

### Fixed
- Spiders stayed calm outdoors at night: like Beta's they go after the player where the light is 11 or less with the night taken off (was 7, the night not counted), and in the light forget their target only now and then (1 in 100 ticks) instead of at once.
- A creature going after another creature (hit by a skeleton's arrow) stopped the game's script: creatures have eyes to look and aim at (Beta's 0.85 of their height).
- A skeleton's arrow no longer hits the spider it rides.

### Added
- Item tooltips tell more with the left Ctrl held, like the modern game's (ItemInfo): the hit in hand and a tool's mining speed (green), armor and where it is worn (blue), how much food heals, how many items a fuel smelts, durability left, a block's hardness and light, the stack size and the inner name with its number. Without Ctrl the tooltip shows the name and a hint. (Beta has no attack speed: none is shown.)
- Snowballs and eggs are thrown with the right button like Beta 1.7.3's (EntitySnowball, EntityEgg): one a click, again every 4 ticks while held, 1.5 blocks a tick along a falling curve; they break on the first block or creature in a puff of bits of their picture. A creature hit takes Beta's "0 damage" (it flinches red, is pushed back and turns on the thrower), a player nothing. An egg hatches a chick 1 time in 8 (then 1 in 32 four of them; chicks, like our breeding, Beta's were grown hens). Dispensers shoot them out as snowballs and eggs instead of dropping them. Seen by network players.
- Eggs can be eaten (ours): holding the right button eats one like other food (half a heart, only when hurt); a tap still throws it, and so does a click at full health.

## [0.0.27] - 2026-11-15

### Changed
- Eating takes holding the right button for 1.6 s (32 ticks) like the modern game instead of Beta's eating at once: the food comes up in front of the mouth and bobs as it is chewed, crumbs and a bite sound every 4 ticks, a burp when it is eaten and heals; letting go sooner eats nothing. Seen from the third person, the hand is at the mouth.

### Fixed
- Music by the time of day was set for tracks that are no longer there, so every track played at any time: calm1 plays at dawn, calm2 by day, calm3 and musicTrack0 (a remix of Door) at night, musicTrack1..4 any time.

## [0.0.26] - 2026-11-15

### Added
- Zombies and skeletons pick up armor for an empty slot, and zombies a sword or axe for an empty hand, lying where they stand (their box grown by a block sideways, like the player's), like the modern game's: worn and held like the player's, a weapon adds its damage over a fist to a zombie's hit, what they picked up always drops when they die (what they spawned with: 8.5%), and one that picked something up no longer despawns. Saved, and sent to network players as it changes.

### Changed
- Zombies and skeletons rest with their arms down (swinging as they walk; a skeleton holds its bow at its side like the player) and raise them straight ahead when they go after someone, smoothly; a skeleton's bow stands upright in front of it then.

## [0.0.25] - 2026-11-15

### Added
- Zombies and skeletons may spawn in armor, like the modern game's: 3.75 / 7.5 / 11.25% of them on Easy / Normal / Hard, mostly leather or gold, rarely chainmail, iron or diamond, from the helmet down (each further piece stopping 1 in 4, on Hard 1 in 10). It spawns already worn (each piece has what is left of it like the modern game's dropped gear: random(1 + random(durability - 3)), mostly a quarter or less, never broken), is drawn like the player's (the same armor layers, now MobModels.armor_pieces for both), takes hits and wears out further like the player's, dropping as worn as it is (Beta's points; a worn-out piece breaks), keeps the sun off with a helmet, is saved and sent to network players, and each piece drops 8.5% of the time when they die.
- Several texture packs at once (Options -> Texture Packs): click a pack to put it on or off, the arrows set the order; the higher pack's files win and the game's fill in the rest, so a pack can hold only a few files. The pack picked before stays on.
- Texture packs can change more than Beta's files (README, "Texture pack layout"): sounds (`sounds/dig/stone1.ogg`..., Ogg, WAV or MP3; a group the pack has replaces the game's), background music (`music/`, the same name replaces a track, `music/dawn|day|night|menu/` for a time or the menus only), jukebox discs (`records/cat.ogg`), the title screen (`title/logo.png`, `title/intro.png`, `title/background.png`, a cube panorama `title/bg/panorama0..5.png`, `title/shade.png`, Beta's `title/splashes.txt`) and the creative inventory (`gui/creative.png`); Beta's `newsound/` and `streaming/` folders work too.
- A pack's `misc/vignette.png` and `misc/water.png` (the picture over the screen under water) are used like Beta's.

### Changed
- Rain and snow drawn like Beta 1.7.3's (EntityRenderer.renderRainSnow): two crossed sheets in every column within 5 blocks (10 with Fancy graphics) instead of one sheet turned to the player within 6, from the first solid block or liquid (rain now falls past flowers, tall grass and torches) to 5 / 10 blocks above the eyes; every column has its own numbers from java.util.Random seeded by its position like the game's (checked against Java's): rain falls at its own speed from its own point of a 32 tick cycle, snow drifts down slowly and sideways each its own way (it fell about ten times too fast); lit by the light of the column (rain: the top of the world, x0.85 + 0.15), see-through like the game's toward the edge. The motion is worked out in the shader, the sheets are made again only when the player moves to another block or every 20 frames.
- Coordinates come from a compass instead of the map: while a compass is anywhere in the inventory the top left corner shows the position (x y z) and the way the player faces, while a clock is, the time and the day ("1:32 Day 9"), in plain white text like the game's; the map no longer has them written on it. With F3 on (release builds) they are under its lines.
- Faster: natural mob spawning looks for the ground skipping empty chunks and works out the night's darkness and the players once per round (it took up to 30 ms at a time); random ticks keep their list of chunks between rounds (updated as columns load and the player moves) and pick in native code; creatures' paths are searched in native code (NativePath: the same search, about 45 times faster), so a creature finding its way no longer stalls a frame; columns left behind unload a few a frame instead of a whole row at once; cave culling works out which chunks to show or hide on its worker thread; every creature's model is made while the world loads instead of when the first of its kind spawns. Flying over new land the worst frames went from about 250 ms to under 35 ms. Linux and Windows builds use the GDScript versions until their native library is rebuilt (tools/build.sh --docker).

### Fixed
- Skeletons held their bow like a small picture raised by the head: they hold it like the player does (RenderPlayer's bow), turned upright in front of them from their arms held out.
- Skeletons stood still once within 10 blocks, waiting for the player: like Beta's (EntitySkeleton in EntityCreature) they find a path the moment they notice the player and keep walking it while they shoot (facing the player, so they step about), now and then dropping it; they shoot within 10 blocks every 30 ticks (was 16 blocks, every 60), and keep after a player out of sight instead of forgetting it at once.
- A texture pack's rain and snow were squeezed to 64 x 64 (Beta's are 64 x 256); an unpacked pack whose files sit in one more folder inside it was not read.
- An opening chest next to blocks left holes: the sides the chest and the blocks beside it hide from each other (the lid's sides, the blocks' sides above the seam) are drawn while the lid is up, and the lid no longer swings into the block behind it (its hinge slides forward as it lifts); it opens to 80 degrees instead of upright.

## [0.0.24] - 2026-11-15

### Added
- Swimming sounds like Beta's: in water a splash every step's distance instead of a footstep, as loud as the stroke is fast, for the player and creatures.
- Sound volumes by category like the game's (Options -> Audio): Master Volume, Music, Jukebox/Note Blocks, Weather, Blocks, Hostile Creatures, Friendly Creatures, Players, Ambient/Environment; the old Sound level moves to every category once, so nothing gets louder.
- Chests open like the modern game's while keeping Beta's look: the top of the cube swings back as a lid in half a second and shuts again when the last player closes it (the closing sound when it shuts), a large chest's two halves as one lid, black inside; every player in a network game sees it. A chest with a solid block on top doesn't open, like Beta's.

### Fixed
- The rear of cows, pigs and sheep was upside down: the bottom face of a model box now lies the same way as the top one, like the game's ModelBox.
- Zombies and other creatures could climb two blocks by catching a wall's top while falling from a jump: they step up only from the ground or when landing, like Beta.
- Beds drawn like Beta's: the legs with the floor seen between them (the sides were filled in), the bottom raised onto the legs, no inner ends where the two halves meet.

### Changed
- On/off settings in Options are one stone button saying ON or OFF (like the other choices) instead of a sliding switch.
- Nightmares only come to a bed in the dark (light 2 or less, torches and the night sky both counted: a lit room or the open night sky is safe) and from spots really dark (light 0-1); the monster is picked evenly from zombies, skeletons, spiders and creepers instead of nearly always spiders.

## [0.0.23] - 2026-11-14

### Added
- Release builds for Windows, Linux (x86_64 and ARM64) and macOS with one command, `tools/build.sh all`; the native library for Linux and Windows is built in Docker (native/docker/), the macOS one locally; an optional GitHub Actions workflow does the same. How: BUILDING.md.
- Create Server in Multiplayer: pick a world, a password and internet access; the game starts a server in the background, joins it and makes you its operator, and asks whether to stop it when you leave.
- A server next to the game: start-server.bat / start-server.command / start-server.sh and server.properties (made next to the game on the first start, with `public-address` for a domain like DuckDNS); `tools/run.sh --server` from the project.
- Error codes for every disconnect and refusal (E101 connection lost ... E502), shown translated on a Disconnected screen with the code; another language is just another .lang file.
- A "Bad connection" mark at the top right when nothing comes from the server for a moment or the ping is high.

### Changed
- Lag isn't taken for cheating: late or bunched-up movement is accepted (up to 5 s at once), moving too fast only sends the player back, a kick needs long and obvious cheating, nothing bans by itself; floods are measured with room for bursts; connections wait up to 30 s before timing out, and the server warns an unstable player first.
- tools/run_server.sh/.bat and native/build.sh are folded into tools/build.sh and tools/run.sh.

## [0.0.22] - 2026-11-14

### Added
- A dedicated server: `tools/run_server.sh` (or `godot --headless --path . -- --server`) runs a world without a local player for many players, set up in server.properties (port, world, seed, type, game mode, difficulty, max players, MOTD, password, whitelist, view distance, spawn protection, idle timeout, PvP, autosave...); commands typed in the console, logs in logs/latest.log, /stop saves and exits. How to deploy: SERVER.md.
- Server password (sent only as a one-time hash), whitelist, bans by IP as well as by computer, operators (/op, /deop) instead of one cheats switch, /whitelist, /ban-ip, /pardon-ip, /save-all, /stop, /kick with a reason, idle kick, limits on waiting and per-address connections.

### Changed
- The host checks everything clients send: movement speed (too fast is sent back), reach and loaded land for every edit, block and item ids, game mode, container changes (no duplicating by taking a stack at the same time), entities and dropped items made by clients, sizes of every message, text (control characters, BBCode), skins; floods and bad data lead to a kick, refusals are logged. Clients no longer pass anything to each other directly, the host saves where it saw a player, far column requests wait, network traffic is compressed. Not compatible with 0.0.21 hosts and clients.
- Less text on the network screens: explanations (what to do with the invite code, the warning, the VPN advice, the port) are in tooltips.

### Changed
- The GUI Scale follows the window like the game's: a chosen scale too big for the window steps down to the largest that fits (the GUI is at least 320 x 240 of its pixels) and back up when the window grows; Auto is the largest that fits. Nothing is rebuilt when the scale comes out the same, so resizing doesn't flicker or reset it.

## [0.0.21] - 2026-11-14

### Added
- Playing over the internet without setup: Open to LAN -> Allow Internet Access asks the router (UPnP) to open the game port and shows an invite code (VE-XXXX-XXXX: the address and a checksum) with a Copy button; the friend pastes it in Direct Connect or Add Server. The ports are closed again when hosting stops. If the router doesn't do UPnP or the provider shares one address (CGNAT), it says so and suggests a VPN (Radmin VPN, ZeroTier). The pause menu's Invite Friends and the /invite command show the code and the LAN addresses again.
- Help & News on the title screen (top left): What's New (from this changelog), Features, Play Together (LAN, internet, VPN, port forwarding), Controls (the current keys) and Game Folder.
- Open Game Folder (title screen help, Options -> General): saves, texture packs, shader packs, screenshots and a mods folder (for later: mods aren't supported yet) are made on start if missing.

### Changed
- A new picture for the game's own texture pack (pack.png).

## [0.0.20] - 2026-11-14

### Added
- Breeding like the modern game: feed two cows, sheep or pigs wheat (chickens seeds) and they fall in love (hearts), find each other and have a baby - half size with a big head, following the adults, grown up after 20 minutes (feeding it speeds that up); parents rest 5 minutes before the next one. Babies drop nothing and can't be sheared, milked or saddled; a lamb takes a parent's wool color.
- Animals follow a player holding their food (wheat, chickens seeds) from 10 blocks and stop 2.5 blocks away, looking at them.
- Zombies and skeletons burning in daylight look for shade or water nearby (under a tree, an overhang, a roof) and stay in the shade by day; a zombie with its player close keeps fighting.

### Changed
- Hurt animals panic properly: 5 seconds of running away from the attacker, faster, to reachable spots (not into walls or off cliffs, into water only when burning).
- Monsters notice a player within 16 blocks, 12.8 while the player sneaks; beyond 3 blocks only one they can see; they give up past 32 blocks or when the player goes creative.

### Fixed
- Sunburn did no damage (the fire was relit every tick and never reached its damage tick); now 1 a second like Beta.

## [0.0.19] - 2026-11-14

### Added
- The surf by the sea (ambient/ocean, looped): twice a second the open water at sea level within 24 blocks is counted; under the open sky and near the sea's height the waves roll in, louder the more sea there is, and fade out in caves, deep down and high up (muffled under water like the other sounds).

### Changed
- Real sounds for falling (damage/fallbig, two variants, and damage/fallsmall) and flint and steel (fire/ignite) instead of the silent placeholders, and the old ones for the player getting hurt (the classic "oof"), the bow, explosions, lava and splashes; damage/hurtflesh added for later. The list of missing sounds is gone: none are missing.

## [0.0.18] - 2026-11-14

### Added
- Creatures make footstep sounds like Beta's (a step of the block underfoot every block walked, snow on a snow layer), and every creature and the player thud when a fall hurts (damage/fallbig above 4, damage/fallsmall).
- Options -> Audio: Echo in Caves (on by default); off, no rays are cast and nothing echoes.
- assets/sounds/MISSING_SOUNDS.md lists the sounds still missing; each has a silent placeholder with its name (fire/ignite, damage/fallbig, damage/fallsmall) to replace with the real file.

### Changed
- Sounds fade with distance like Beta 1.7.3's: evenly to nothing at 16 blocks (farther for louder ones, an explosion 64), instead of a falloff that was too quiet near and too loud far.
- Footsteps at Beta's volume (0.15, were twice as loud), breaking a block at Beta's pitch (0.8, no random), creatures' and the player's sounds at Beta's pitch spread (mostly near 1).

### Removed
- The generated placeholder sound for flint and steel (only the sounds added by hand are left).

## [0.0.17] - 2026-11-14

### Added
- Caves and closed rooms echo: four times a second rays from the eyes in 14 directions find how closed in the player is and how big the space is; with no sky light at the eyes a reverb comes in over a second or so - short and dull in a tunnel, longer and ringing in a big hall - and fades out again outside. The walls' material counts: stone and glass throw the sound back, wood, earth and snow soak some of it up, wool almost all (a wooden house echoes softly, a stone cave rings). The music stays dry.
- Sounds are muffled under water like the modern game's: with the eyes in water a low-pass filter takes the highs away (down to 700 Hz) and they get 5 dB quieter, fading in and out in a quarter of a second; the music stays as it is.

## [0.0.16] - 2026-11-14

### Added
- The recipe for wool from 4 string (the only Beta 1.7.3 recipe that was missing).
- Lapis ore smelts into lapis lazuli (like coal and redstone ore already do).
- Furnace fuel like Beta's: every wooden block burns 300 ticks (wooden stairs, bookshelf, fence, note block, jukebox, wooden pressure plate, trapdoor), saplings 100; and like the modern game: ladder 300, wooden slab 150, wooden door and sign 200, bowl 100, bow and fishing rod 300, boat 1200.

### Fixed
- Lying logs didn't smelt into charcoal, and turned blocks (lying logs, top slabs, stair variants) didn't burn as fuel like their normal block.

## [0.0.15] - 2026-11-14

### Added
- Stairs take corner shapes like the modern game's (inner and outer corners from the stairs around them, both halves), updated as neighbors change.

### Changed
- The debug world's time and weather stand still (always noon, clear), so every water and lava level stays as shown.
- The selection outline follows only the outer edges of a block's shape (no lines between the parts of stairs, fences, slabs...).
- Stairs keep their texture's direction whichever way they face (like the game's uvlock): the planks line up as if cut from a block.
- Fences join full solid blocks next to them (stone, planks, glass...), not only other fences; not leaves or pumpkins, like the modern game.

## [0.0.14] - 2026-11-14

### Changed
- The creeper about to explode like Beta's RenderCreeper: it swells hardly at first and fast at the end (+40% wide, +10% tall, trembling) and a faint white (at most 20%, mixed like Beta's) blinks over its skin every tenth of the fuse, instead of turning white.
- The boat's texture in the colors of oak planks.
- Boats row faster: up to about 6 blocks a second (was 4.5).

## [0.0.13] - 2026-11-14

### Added
- Blocks placed like the modern game's: logs lie along the axis of the clicked side (new lying oak, birch and spruce logs), stairs and slabs go upside down / on top when placed against a ceiling or the upper half of a side (new upside-down stairs and top slabs; a slab clicked on its open face or into a cell with the same slab makes a double slab), dispensers face up or down when looking steeply.
- World Diorama (F6, was the isometric view): the area around the player cut out as a block on a sky background, with Close, Center Camera, Area, Zoom, Tilt, Time, Fog, Clouds, Players, Mobs, Lighting and screenshot size/background on the right; drag to move, right-drag to turn, wheel to zoom, < > to turn by 90°, Take Screenshot and a button opening the screenshots folder.
- In bed: a Leave Bed button at the bottom, Enter opens the chat; the bed's refusals show over the hotbar.

### Changed
- The Options screen: categories with icons on the left (General, Player, Audio, Video, Controls, Texture Packs, Language, World in a world, Search), the chosen category's settings on the right, each with a line to its control, ON/OFF switches, sliders, a reset arrow when changed and folding groups.
- A creature's death is a puff of white and gray clouds rising over it, and explosions a big white-gray cloud breaking into puffs with dark specks (new explosion pictures, assets/textures/extra/explosion.png).
- A door goes on the edge of the half of the block the cursor points at; a placed boat faces where the player looks.
- The view in bed is fixed (no turning the head); the chat sits above the hotbar and hearts instead of over them.
- Opening the pause menu closes the chat being typed.

### Fixed
- The sleep darkness, the flames when burning and the pumpkin's view were drawn over the menus.
- Turned and upside-down cobblestone stairs and stone slabs had weak blast resistance.

## [0.0.12] - 2026-11-13

### Added
- Inventory controls like Minecraft's: drag a stack over slots to split it evenly (left button) or put one in each (right button; middle button fills them in creative), Shift-drag to quick-move every slot passed over, double-click to collect matching items into the held stack (Shift+double-click moves all of them), middle click in creative to take a full stack.

### Changed
- The pause menu laid out like the game's: Back to Game; Achievements and Statistics side by side; Options... and Open to LAN side by side; Save and Quit to Title, starting a quarter of the screen down.

### Fixed
- Dropped items on the edge of a block were set down into the next block, pushed out up and fell again over and over.
- The breaking cracks stayed on their first picture after going back into a world (the cached crack meshes kept the previous world's material).
- The bottom of grass blocks was tinted with the grass color instead of being plain dirt.

## [0.0.11] - 2026-11-13

### Added
- Hardcore game mode: survival on Hard that can't be changed, cheats off, one life; on death "Game over!" with only Delete World, which removes the world.

### Changed
- The boot splash is a pixel-art Godot logo with "Godot Engine" in the game's font on the menus' dark color, drawn again in the middle once the window takes its saved size (it used to stay in a corner).

## [0.0.10] - 2026-11-13

### Added
- World types Floating Islands (Beta's biomes, trees, ores and springs on islands in the sky over the void), Island (one big island in an endless sea; seas inside it become low land) and Debug Mode (every block in every state in a grid on a stone floor, and a row of every creature and its looks standing still; nothing ticks or spawns there).
- Bonus Chest option when creating a world: a chest of wood, wooden tools, apples and bread by the spawn with a torch on each side.
- The multiplayer screen is a server list like Minecraft's: saved servers (Add, Edit, Delete, Direct Connect, Refresh) with their message, players and signal bars from a status ping that doesn't join, and the games on the local network below them.
- The survival inventory shows the player (skin, armor, item in hand) in the black box, turning toward the mouse like Beta's.
- Creatures cast Beta's round shadow (misc/shadow.png) on the blocks under them, fainter the higher they are, in the dark and with distance; Fancy graphics only.
- Empty armor slots in the inventory show the outlines of a helmet, chestplate, leggings and boots (items.png's last column, like Beta's).
- Commands: target selectors (@p @a @r @s @e with filters), local coordinates (^ ^ ^), /execute, /summon, /kill, /damage, /clear, /clone, /setworldspawn, /difficulty, /particle, /playsound, /list, /me, /msg (/tell, /w); /give with count and damage, /tp to entities and with rotation, /fill and /setblock modes, /help pages; game rules doMobSpawning, mobGriefing, doFireTick, doMobLoot, doTileDrops and sendCommandFeedback. Command messages are translated.
- Nightmares like Beta's: you can't sleep with monsters within 8 blocks of the bed, and sleeping in the dark a zombie, skeleton or spider that can walk to you may appear by the bed and wake you (the night isn't skipped).

### Changed
- The Create New World screen: game mode and world type, cheats and the bonus chest two to a row, Create New World and Cancel side by side, over the menu's darker band.
- Lying down in a bed and getting up move the view at once instead of sliding.
- The player in the inventory stays inside its black box.

## [0.0.9] - 2026-11-13

### Fixed
- The unnamed files given to spiders, wolves and chickens were not theirs (stone-like knocks, taps on thin wood, dull thuds); the dull thuds are now the sound of digging snow.

### Changed
- Real spider, wolf and chicken sounds. Wolves speak like Beta's EntityWolf: they growl when angry, else now and then whine (tame and hurt below 10 health) or pant, else bark; they shake themselves dry with a sound when they come out of the water. A chicken laying an egg plops.
- Real sounds for chests (one opening, three closings), doors and trapdoors, fire, water putting out lava and fire, TNT's and creepers' fuse, pistons, the note block's bass, bass drum, snare and hi-hat, sheep (their bleat when hurt and dying too, like Beta's), lava and its pops, clicks and picking items up. Only the flint and steel's sound is still a placeholder.

## [0.0.8] - 2026-11-13

### Changed
- Real sounds instead of the made-up placeholders: footsteps and digging (grass, gravel, sand, stone, cloth; digging wood), rain and thunder, the player's hurt sound, cows, pigs, creepers, skeletons, zombies, slimes, spiders, wolves and chickens, and the bow, arrow hits, a tool breaking, burping, clicks, eating, explosions, splashes, picking up, water and the note block's harp. Kept as they were: snow and wood footsteps, sheep, chests, doors, fire, lava, fuses, pistons and the other notes.

- Music: the game's own tracks as .ogg (calm1–3, musicTrack0–4); the time-of-day table still names the old tracks, so every track plays at any time for now.
- Footstep sounds on wood and snow, cave sounds and lava sounds replaced with new recordings.

### Fixed
- The glass sound no longer counts twice (import files left of the old glass sounds were removed); the same for the old music's import files.

## [0.0.7] - 2026-11-13

### Fixed
- The inventory's slots stand where Beta 1.7.3's inventory.png has them (crafting grid at 88, 26, its result at 144, 36, the title at 86, 16); the small chest is put together from container.png like Beta's (its inventory part from row 126) and the dispenser's and large chest's inventories are at Beta's rows.
- The sun and the moon are added onto the sky like Beta's (GL_ONE, GL_ONE): Beta's pictures have a black background, which drew a black square.
- Bits of broken tall grass, ferns and leaves take the biome's color where they were (terrain.png draws them gray, like Beta's).
- The Tab list's signal bars come from their own picture (`extra/signal_bars.png`): Beta's icons.png has none.
- The held item's name shows above the hearts (and the air bubbles) instead of on them.
- Mobs no longer jerk while walking: they speed up and slow down like Beta's (acceleration and friction instead of a set speed each tick), and their turning is smoothed between ticks.
- A hit mob is thrown back and hops up (Beta's knockback, 0.4 back and 0.4 up) instead of sliding along the ground.
- A creeper killed by a skeleton's arrow drops a music disc (13 or cat), like Beta's.
- The air bubbles no longer blink while swimming deep under water: the top of a water block with water above it counted as out of the water (Beta's water fills such a block).
- No arm and leg swinging while sitting in a boat, a minecart or on a pig.
- Items held in another player's (and the third-person view's) hand stand like Beta 1.7.3's (RenderPlayer / RenderBiped): blocks small in front of the fist, tools and swords pointing ahead, other items a picture turned like Beta's, the bow held up by its grip.
- The leaves table (`Blocks.fast_leaves_table`) is filled apart and then put in place: a generator thread asking for it at the same moment could write past its end.

### Changed
- The arm swings faster (6 ticks, the game's); a click starts a new swing once the current one is past its middle, while breaking swings follow each other whole, and each swing is sent to the other players once (not every frame).
- Mob textures are the classic game's (Beta 1.7.3's mob/*.png, 64 x 32); every model fits them as they are.
- The wolf's model is Beta's (ModelWolf) exactly: its mane around the neck in front of the body (it sat inside the body), every part 1 pixel to the side like Beta's, so the head turns about its own middle; no collar (Beta's tame wolves had none: their skin is wolf_tame.png).
- The body follows the head like Beta's: the head turns alone up to 75 degrees, the body turns toward where the player goes (in a boat or on a pig: where it goes), so turning the view in a boat no longer turns the whole body at once; in a minecart the body turns round with the view. Other players' bodies too.
- Mob spawning like Beta 1.7.3's (SpawnerAnimals): kinds by weight (sheep 12, pig 10, chicken 10, cow 8; wolves 2 in forests and taiga; spider, zombie, skeleton, creeper and slime 10 each), groups spreading by hops of up to 5 blocks (at most 4, wolves 8), animals on grass (snowy too) in light above 8, monsters where the sky light is under a random 0..31 and the light under a random 0..7, slimes in slime chunks below y 16 (1 try in 10); up to 70 monsters, 15 animals and 5 squid counted within 128 blocks of each player.
- Hurt mobs turn red like Beta's: their colors mixed 40% with red at the light they stand in (no turning aside when hit).
- Wolves are neutral like Beta's: a wild wolf only attacks a player who hit it, and then its pack within 16 blocks with it; tame wolves follow their owner along paths (closer than 5 blocks they stop, farther than 12 they come to the owner's side), attack what hits their owner or what the owner hits, and calm down when the target is dead or far.
- Peaceful animals run away from what hurt them (along a path, faster), wander along short paths, and monsters notice the player within 16 blocks even without seeing them and go around walls to them.
- Spiders' eyes glow like Beta's: mob/spider_eyes.png drawn over the head at full brightness, also in the dark (model parts may be "glow").

- terrain.png is the classic game's (the textures of Beta 1.7.3). Its tiles stand where ours stood; fire, water and lava are drawn by their animations as before (the atlas only has placeholders there, like Beta's).
- Chests are blocks like Beta 1.7.3's instead of the modern lidded model: a full cube with terrain.png's chest tiles (top and bottom 25, sides 26, a single chest's front 27; a large chest's halves 41 / 42 in front and 58 / 57 behind), so a texture pack's terrain.png draws them too. The chest atlas is no longer used (`extra/unused/chest-atlas.png`).
- Spruce and birch planks (blocks Beta did not have) keep their own tiles in `extra/terrain_extra.png`, used where a terrain.png has nothing in those places (`TexturePacks.GAME_TILES`).

### Added
- Paths for creatures (`Pathfinder`): A* on the block grid, a bit smarter than Beta's: around walls and holes, up one block (a jump), down at most 3, through water, never into lava, fire, cactus or onto fences. The cells searched are shared out among all creatures each tick (`Pathfinder.NODE_BUDGET`), so many of them don't slow the game; a path is found again when the goal moves away or the creature gets stuck.
- Music for the time of day: the tracks still come now and then (every 10 to 20 minutes, like the game), now one for the part of the day (`Sounds.MUSIC_TIMES`): at dawn (about 04:30 to 08:00) "the_dawn", by day "empty_pixel_world" and "early_exploration", in the evening and at night "the_forest_glitches" and "deep_cavern_silence"; the calm tracks play any time, and the menus play as by day.

## [0.0.6] - 2026-11-13

### Changed
- Trees exactly like Beta 1.7.3's generators (`TreeShapes`; `NativeBetaGenerator` the same, block for block): oaks and birches with Beta's room check (the whole tree's volume, not only the trunk); spruces (WorldGenTaiga2) with rings growing from the top and starting over, the trunk 0..2 shorter than the leaves; pines (WorldGenTaiga1) with a long bare trunk and a cone of leaves 1..5 wide; big oaks (WorldGenBigTree, 5..16 high) with leaf clusters at the ends of sloping branches. Kinds and numbers by biome like Beta: big oaks 1 in 10 everywhere, 1 in 3 in rainforests and in forests' oaks; only forests, rainforests, seasonal forests and taiga get many trees (savannas, shrublands and swamps one now and then). Each tree stays in its column (bigger kinds further from its edges). Saplings grow the same trees (an oak sometimes a big one).
- Far chunks (more than 8 columns away) draw leaves opaque like Fast graphics; nearer ones as before (Fancy). Switching Fast / Fancy in the game updates the native mesher's tables too.

### Fixed
- Chunks of only air or uniform light shared their arrays by reference (GDScript's packed arrays are not copied on write): a block set or light changed in one such chunk showed in all of them. A chunk now takes its own copy before changing one (`ChunkData.own_blocks`, `own_light`, `own_block_light`).

### Changed
- Far terrain is part of the render distance instead of its own setting: Render Distance goes up to 32 chunks; up to 16 every chunk is real, beyond 16 the real chunks stop at 16 and the far terrain draws the rest out to the chosen distance (`FarTerrain.REAL_LIMIT`). The "Far Terrain" setting is gone.

### Added
- Far terrain (Video Settings → Far Terrain: OFF, 16, 24 or 32 chunks; 16 by default): beyond the render distance the land is drawn simplified, its quality falling off with distance, so far mountains and coasts are seen (`FarTerrain`, `far_terrain.gdshader`). Far columns are read from the save or generated on worker threads once the near ones are done and kept only as summaries (each block column's top block, the block under it and its biome tint); they are drawn with the blocks' own textures repeated per block (leaves as Beta's fast leaves), tinted and shaded per face like the blocks and darkened at night, in cells of 1 block next to the real chunks, 2 blocks 4 chunks further and 4 blocks beyond 10: a cell's top at its highest block (equal tops in a row are one quad), walls down to the lower neighbor (the top block's side, then the block under it). One mesh per 8 x 8 columns, built on a worker thread, left out where the real chunks are; moving rebuilds only the regions where the cell size changes. The fog moves out to the far edge. Measured (24 chunks, flying 30 s): no frame over 33 ms, about +10 MB.
- Texture packs: a pack's particles.png (smoke, flames, lava, notes, hearts, rain splashes at their Beta places; the game's own critical hits and sweep stay) and font/default.png (Beta's letters and signs, each as wide as its pixels like Beta's; letters it has not, Cyrillic, come from the game's font) are used too.
- World types (Create New World → World Type): **Default** is Beta 1.7.3's world, 128 blocks high with the sea at 64 and the bedrock floor at 0-4 (building stops at 128: "Height limit for building is 128 blocks"); **Tall Mountains** is the same land 256 high with the sea at 64 and mountains up to about 190. The world's layout is kept in level.cfg (`terrain`) and sent to network clients (`WorldSave.layout`: height, sea, and for the generator where the classic part starts, whether there is the old deep layer, how high it reaches; `BetaGenerator.set_layout`, `NativeBetaGenerator.set_layout`). Clouds float 44 blocks above the world's sea (108, like Beta), spawning, slimes and the title screen's world follow it.
- Texture packs exactly like Beta 1.7.3's: a pack is a .zip (or a folder) with the jar's files at their places (pack.txt, pack.png, terrain.png, particles.png, gui/gui.png, gui/icons.png, gui/items.png, gui/background.png, gui/inventory.png, gui/crafting.png, gui/furnace.png, gui/container.png, gui/trap.png, mob/*.png, armor/*.png, item/arrows.png, item/boat.png, item/cart.png, art/kz.png, environment/rain.png, snow.png, clouds.png, misc/dial.png, mapbg.png, mapicons.png, pumpkinblur.png, grasscolor.png, foliagecolor.png, terrain/sun.png, moon.png, title/mclogo.png, mojang.png; also zipped inside a folder). Pictures are used at Beta's sizes (another size is scaled to it), and the GUI is cut from Beta's sheets where Beta draws it (the hotbar and buttons from gui.png, the crosshair from icons.png, the chest window from container.png, the furnace's fire and arrow from furnace.png). The Texture Packs screen shows each pack's pack.png and the two lines of its pack.txt. Now from the pack too: the clouds' shape (environment/clouds.png), grass and foliage colors looked up in Beta's color maps, the paintings (kz.png), the wolf's tame and angry skins, the title logo (mclogo.png, its two halves) and the Mojang screen.

### Changed
- Chunks of only air, of full sky light or of no block light share one array each (copied when changed): a world at render distance 8 takes 228 MB instead of 292 (Default worlds; 186 MB with Tall Mountains).
- Column generation's heightmap and chunk counts are native (`NativeLight.heightmap`, `chunk_counts`): a column takes about 2 ms on its thread instead of 5.
- `assets/textures` is laid out like a Beta 1.7.3 texture pack, so the game's own textures are the "Default" pack: the pictures moved to Beta's names and places (items.png → gui/items.png, mobs/ → mob/ with player.png → char.png, armor → armor/cloth_1.png..., boat and minecart → item/, sun and moon → terrain/, the paintings at kz.png's places) and the GUI pieces are put together into Beta's sheets (gui.png, inventory.png, crafting.png, furnace.png, container.png, trap.png, background.png), pixel for pixel the same. The game's own pictures with no place in Beta are in `extra/` (the creative inventory, the particle and chest atlases, the title logo, blur and intro, the wolf's collar); ones nothing uses are in `extra/unused/`. The clouds' pattern and the grass and foliage colors, worked out in code before, are now pictures (environment/clouds.png, misc/grasscolor.png, misc/foliagecolor.png) made from the same numbers. The texture tools (`tools/make_*.py`) write to the new places.
- Worlds made 128 high before are no longer moved up into a 256 high world: they open as Default worlds (their columns filled with air above). Worlds made 256 high (the sea at 128) open as they were.

### Changed
- Many block changes at once are lit together: a network packet of block changes, /fill and explosions set their blocks first and then work out the light near the player in one native call for the whole area (`VoxelWorld.begin_batch` / `end_batch`, `NativeLight.relight_edits`) instead of one call per block with the arrays of 9 columns. Measured on a client: digging 16 x 8 x 16 blocks 188 -> 21 ms, a 32 x 2 x 32 roof 248 -> 43 ms, 216 glowstone 39 -> 4 ms; the light is the same as block by block (compared with lighting the columns anew). Columns, entity snapshots and dropped items were measured too and stay in GDScript (a column: 0.1 ms to gather, 0.3 ms to compress, 0.1 ms to unpack; 85 entities' state 0.2 ms).

### Added
- Multiplayer, fourth step: jukeboxes, cakes, beds and chest minecarts for clients. A client's disc goes into the host's jukebox (or comes out) through the host, and everyone hears the record (`Net.send_jukebox`, `record_changed`). Clients eat cake themselves (the bite goes to the host). Clients sleep in beds; the night passes only when every player is asleep, like the game's servers (`Net.all_asleep`; a client wakes up when the host's morning comes). A client opens the host's chest minecart like a chest (`Net.open_cart_container`: containers are keyed by a block position or a cart's net id).

## [0.0.5] - 2026-11-12

### Added
- Multiplayer, third step: containers, signs and creatures for everyone. Chests (large ones and dungeon chests too), furnaces and dispensers stay the host's: a client asks to open one, the host sends what is inside and the window opens on it; then each side sends only the slots that changed (the client what its player moved, the host 10 times a second what changed there: its player, the furnace, a dispenser, another client) and the furnace's fire and arrow (`Net.open_container`, `_send_container_changes`; the window closes when the block is broken). Sign text is shared: sent with the column and to everyone when written (`VoxelWorld.column_signs_for_network`, `apply_network_sign`). Clients shear and dye sheep, saddle and ride pigs, milk cows, tame wolves and make them sit, and feed coal to furnace minecarts: the host does it for a stand-in of that player with the item in its hand (`NetPlayerProxy`, `Net.send_interact`) and sends back what is left in the hand. Creatures spawn around every player, not only the host (the caps grow with the players).
- Multiplayer, second step: the world's creatures and things are shared. The host's creatures, boats, minecarts, arrows, primed TNT, paintings and lightning are sent 10 times a second to each client within 96 blocks (new ones with their whole state) and drawn there as copies following the host's (`Entity.puppet`, `net_state`, `apply_net_state`; their hurt sound plays too); what a client makes (an arrow shot, a boat or cart put down, a painting, lit TNT) the host makes (`EntityManager.spawn` hands it over). Clients hit the host's creatures (the host checks the distance), ride its boats and minecarts and steer them (`Entity.remote_rider`). Creatures go after the nearest player, the network game's others too (`RemotePlayer` acts like a player to them: damage and knockback go to its owner), arrows hit them, and players hurt each other (aimed at like creatures). Dropped items are shared within 48 blocks: drops and throws go through the host, a client picks items up by asking it (`ItemEntities.net_items`, `take_for_network`). The host keeps each client's player (place, inventory, armor, health) by its tag in the world's save and gives it back on joining.
- Allow Cheats, like the game: in Create New World (on with creative, off with survival, until set by hand; saved per world, worlds from before keep them on) and in the new "Open to LAN" screen ("Settings for Other Players": the game mode new players get and whether cheats are allowed, for the host too while the world is open). Without cheats only /help, /seed, /say and the host's /players, /kick, /ban, /pardon run. A client's world commands (/time, /weather, /gamerule, /tick, /setblock, /fill) run on the host, from where that player is, the answer in its chat.

### Added
- Building and running from the console, without the editor: `tools/build.sh` (release or `--debug`, a zip or `--app`, `--native` to rebuild the C++ library first; imports, exports the "macOS" preset, checks the signature and the native library) and `tools/run.sh` (`--release` shows the release build's short F3 screen: `DebugScreen` reads `--short-f3`).

### Fixed
- Exported games never loaded the native library (they ran on the slow GDScript code): a bare `.dylib` in `bin/` was not found in the app's `Contents/Frameworks` ("relative path not allowed in hardened program"). `native/build.sh` now packs it as `bin/libvoxel_native.framework`, like godot-cpp's template, which exported games load; it is kept out of the resource pack.

### Added
- Player Settings (Options): the name, its color (the game's chat colors or a rainbow) and the skin: the player's own from a PNG file (64 x 64, or the classic 64 x 32 widened like the game does) or the default one, with a preview of the front and the back (`PlayerProfile`, `PlayerSettingsScreen`; kept in user://player.cfg and user://skins/custom.png). The skin is worn by the player's model and hand; the name color shows in the chat (a rainbow letter by letter), above the head and in the Tab list. In network games everyone's skin and name color are sent to the others (`Net.looks`).
- Telling players apart and keeping bots out of network games: a joining player answers the host's challenge with its tag, a hash of its computer's hashed id (`OS.get_unique_id`, never sent) and the server's own salt: the same on one server (bans stick), different on every other one (servers can't follow a player), nothing about the computer in it (`PlayerProfile.tag_for_server`). The host bans by tag (user://bans.cfg), allows 3 connections and 5 tries in 30 s from one address, drops connections that don't introduce themselves within 5 s and kicks players flooding the chat, edits or column requests. Host commands: `/players` (names, tags, addresses), `/kick`, `/ban`, `/pardon`. A changed client could fake its tag: this stops casual bots and spam, not a determined attacker or a network-level flood.

## [0.0.4] - 2026-11-12

### Added
- Zombies and skeletons get into a free boat or minecart they bump into (when either is moving), like the game's minecarts: one rider each, carried along sitting with the legs ahead, still looking about and attacking (skeletons shoot from it); out again when the boat or cart breaks. An occupied boat or cart can't be taken by the player (`Entity.vehicle`, `Entity.rider`, `Entity.take_creature`, `Entity.seat_free`).
- Multiplayer, first step (stage 15; `Net` autoload, `scripts/net/`): the classic game's way, a player opens the world from the pause menu ("Open to LAN", port 25565) and is the host; others join from "Multiplayer" on the title screen, by address or from the games found on the local network (UDP broadcast on port 4445). Godot's multiplayer over ENet.
  - The host runs the world (liquids, growth, redstone, ticks, saving). A client generates the columns nobody has changed itself (the same blocks from the same seed) and gets the changed ones from the host (compressed); every block change goes to the clients a frame at a time; the host keeps the columns around the other players loaded.
  - A client's edits (breaking, placing, buckets, beds, doors) show at once and are made by the host with all their effects; levers, buttons, repeaters, doors, trapdoors and note blocks are used by the host. A client's drops go straight into its inventory (dropped items are the host's for now).
  - Players see each other (`RemotePlayer`: the player model with the skin, the name above, walking, sneaking, sitting, sleeping, swinging, the item in hand); chat, the time of day and the weather are shared; joining and leaving show in the chat. The game goes on behind the pause menu while online.
  - Tab shows the players (`PlayerList`): the face from the skin, the name and the signal bars from `icons.png` by the round trip the host measures each second (under 150 ms five bars ... a red cross while unknown).
  - Not shared yet (the next step): creatures, dropped items, chests, furnaces and dispensers, arrows, minecarts and boats, signs' text; a client's player is not saved.

### Added
- Ice melts into water like the classic game where block light is brighter than 8 (a torch within about 5 blocks, lava or fire next to it), and now and then outside the cold biomes (`LiquidBehavior.ice_random_tick`).
- Boats burn up in lava (smoke, flames, embers and a hiss) and are pushed aside by the player and creatures pressing against them (the game's entity collision).
- Buttons and levers go on all six sides: buttons on floors and ceilings, levers hanging from ceilings (new block states appended, ids stay stable).
- The sitting pose: riding a boat, a minecart or a pig the player sits with the legs straight ahead and the arms forward, like the game's.

### Changed
- Fences are not full blocks: aimed at and outlined as their post and bars, bumped into as the post and bars 1.5 blocks high (`BlockType.outline_boxes`, `Blocks.outline_table`).
- The ladder is a flat item: its picture in the inventory, in hand and on the ground.
- The cracks of a block being broken follow its shape (slabs, fences, torches, pistons...) at their own size: each face shows the part of the crack picture its place in the block covers, nothing stretched or squeezed.

### Fixed
- Boats pushed by creatures no longer smash on the shore (only rowing into it at full speed does).
- Riding looked like floating: the rider stood at the old height with the legs held out. Now the hips rest on the seat (`Entity.seat_height`: a boat's bottom, a minecart's floor, a pig's back; `Player.seat_offset`), the view lowered with them.
- Ice in lava let you see through the lava: lava faces next to ice were left out (meant for water under ice only).
- Riding jittered: the rider (ticked on its own clock) followed the boat or cart (ticked on the world's) a tick at a time; now the rider is drawn on the seat where the vehicle is drawn.
- An extended piston could be aimed through where the head's arm enters it, and a sliding block blinked out for a frame when it arrived (it waits now until the chunk's new mesh is up).
- Curved rails turning south-west and north-east bulged the wrong way (four curves made a cross instead of a circle).

### Added
- The void near the bedrock like the game since Beta 1.8: below y 32 the fog turns black, and in survival it closes in where no sky light reaches (down to 5 blocks at the very bottom); dark specks of dust drift in the air below y 8, more the deeper (`VoxelWorld._void_dust`, `BlockParticles.void_speck`).
- Lava bubbles: now and then tiny embers jump out of a lava surface (besides the pops).
- Rain and snow hiss into steam on lava, fire and torches (with a fizz now and then); snow falling on water melts into white specks; rain splashes use the game's splash picture, smaller on water with a few droplets.
- Items burn: in lava at once with smoke, a flame, embers and a fizz; in fire after 5 ticks with flames on them.
- Boats are solid like Beta's: the player and creatures bump into them and can stand on them, boats bump into each other (`EntityPhysics.solid_entities`, the moving entity ignores its own box).
- The map is held in both hands like the classic game's (`HeldItem._map_pose`, Beta 1.8's first-person map): looking ahead it sits low and tilted, half out of the view; looking down it comes up to the eyes; it swings like an item and is lit by the light at the player. The player's marker is the game's pixel icon (`textures/misc/map_icons.png`), turned the way they look in 16 steps, a white dot at the edge when they are off the map. The player's coordinates are written small across the top of the map.

### Changed
- The F3 screen is complete only in debug builds (the editor, debug exports); a release build shows the game and its version, the frame rate, the memory and video memory used and how much the world takes on disk (`DebugScreen.full`); the coordinates are on the map.
- Boats are slower with inertia: rowing pushes a little each tick (half as much backwards) and water drag takes 3% a tick, so a boat picks up speed smoothly to about 4.5 blocks a second (Beta's went 8) and glides on, slowing down little by little, when the rowing stops; it turns smoothly toward where it goes and only smashes on the shore at full speed (0.2 blocks a tick).
- Particles are simulated and drawn in native code (`NativeParticles`, `native/src/native_particles.cpp`): movement, stopping on blocks, animation frames and the MultiMesh buffer in one call; the world is asked once a tick for the few cells the particles touch. A tick of about 1200 bits takes 0.3 ms instead of 19, drawing 0.04 ms instead of 0.4. Without the library the GDScript simulation is used.
- Lit particles (block bits, crumbs, smoke, steam, splashes) take the light where they are every tick, like the classic game, instead of where they started.

### Fixed
- The map in hand was drawn over the pause menu (it was a 2D overlay; now it is in the 3D view).
- The bits of a broken block were almost black: they took the light inside the block (none). Light inside a solid block is now the brightest light next to it (`VoxelWorld.brightness_at`).
- Blocks drawn as things glowed at full light in the dark (a dropped block item in a cave, falling sand, primed TNT, a minecart's chest or furnace, a block held by the player or a creature, a block pushed by a piston, the pumpkin on the player's head): their mesh had full light baked in. The block shaders take the light where the thing is through a per-instance `entity_light` (`FallingBlocks.light`).
- A possible crash on quitting: the saved world (with the generator's native objects) is let go while the engine still runs (`TickLoop._exit_tree`).

## [0.0.3] - 2026-11-12

### Added
- Native code (GDExtension, `native/`, godot-cpp 4.5): `native/build.sh` builds `bin/libvoxel_native.dylib` (macOS, Apple Silicon and Intel), loaded through `bin/voxel_native.gdextension`. First in it: a column's sky light and block light (`NativeLight.compute_column`), the same light cell for cell as `SkyLight` / `BlockLight` and about 55 times faster (9 ms a column instead of ~500 with many lights); the whole render distance 12 is ready in about 23 s instead of 28 (the loading screen goes after 16 s instead of 21.5). Without the library the GDScript light is used.
- Chunk meshes are built in native code too (`NativeMesher.build_chunk`: padding, faces, smooth light and AO, liquids, plants, block models and cave-culling connectivity): the same arrays as `ChunkMesher.build` (checked on 144 chunks with every kind of block and every Smooth Lighting setting) about 34 times faster (0.14 ms a chunk instead of 4.6). With both, the loading screen goes after about 11 s instead of 21.5, the whole render distance 12 is ready in about 20 s instead of 28; generation is what is left.
- World generation in native code too (`NativeBetaGenerator`: terrain, surface, caves, lakes, dungeons, ores, trees, plants, springs, ice and snow, the deep layer): the same columns block for block as `BetaGenerator` (checked on 42 columns of three seeds, tall and classic terrain) with the generator's own noises and Godot's random numbers (PCG32 rewritten, checked number for number), about 26 times faster (1.2 ms a column instead of 30). With everything native, the loading screen goes after about 8 s (21.5 before the native code) and the whole render distance 12 is ready in about 11 s (28 before); flying on, 1 frame over 33 ms in 25 seconds. The library is built without fused multiply-add so floats round like GDScript's.
- Light after a block change near the player in native code too (`NativeLight.relight_edit`, the same removal and spreading as `_relight` / `_relight_block_light`, checked on 400 random edits: torches, glowstone, lava, glass, leaves, water, stone, holes and shafts to the sky): about 5 times faster (0.28 ms an edit instead of 1.35) and done at once, no light left to spread over the next frames. The title screen's world is lit and meshed in native code too (shown after about 0.8 s).
- Particles from the game's particle atlas (`textures/particles-atlas.png`), animated frame by frame like the game's (`BlockParticles`, `particle.gdshader`): smoke shrinks as it rises (torches, furnaces, fire going out, creatures gone), flames on torches and furnaces, lava sparks, red hearts (taming), colored notes, water splashes, reddust, explosions in big fading puffs with smoke.
- Fight particles and critical hits like the game since Beta 1.8: hitting a creature spills dark hurt hearts (one per 2 damage); hitting while falling is a critical hit (half again as hard) with white stars; a sword hit on the ground shows the sweep's arc in front of the player.
- Pistons move blocks smoothly like Beta: pushed and pulled blocks and the head slide over 2 ticks; their cells hold an invisible `moving_piston` block that becomes the block when it arrives, a retracting head slides back in, blocks still sliding arrive at once before the piston moves again or the world is saved (`PistonBehavior.start_moving`).
- A carved pumpkin can be worn on the head (the helmet slot, Shift-click too): in first person the view is through its eyes (`textures/misc/pumpkinblur.png`, ours, texture packs can replace it), in third person the player wears it.
- Bookshelves burn like the game's (catch 30, burn 20).
- Drawing the bow like the game since Beta 1.8: hold the button to draw (the string goes back in three steps, with an arrow on it: pictures drawn into free cells of the item atlas unless a texture pack has them, `Items.BOW_PULL_TILES`), let go to shoot; a longer draw shoots faster (up to 3 blocks a tick) and harder (up to 4), a barely drawn bow doesn't shoot. In first person the bow is held up and pulled toward the eye (Beta 1.8's pose, shaking when fully drawn), the view zooms in a little, and in third person both arms come up along the view.
- Carved pumpkins: pumpkins grow whole now; shears and a pumpkin in the crafting grid make a carved pumpkin (the shears stay, a little worn), and a carved pumpkin over a torch makes a jack o'lantern. Pumpkins in worlds from before stay carved.
- The world is twice as high and twice as deep: 256 blocks with the sea at 128. The classic generator makes the part from y 64 up exactly as before (moved 64 blocks up); under it a new deep layer of stone with its own caves (lava below y 10), lava lakes, dungeons, ores at the classic heights and the bedrock floor. New worlds have hills about twice as high and mountains higher still (up to about 100 blocks above the sea); clouds float at 172.
- Worlds made when the world was 128 high are converted when opened: the world folder is first copied to `user://backups/<world>_height_128`, the player, the bed, block entities, items, creatures and paintings move 64 blocks up, and each column is converted the first time it loads (its blocks 64 up, the old bedrock floor turned into the deep layer, `WorldGenerator.convert_legacy`). Their new terrain keeps the classic shape, so it joins the old columns without seams. The level file records the world's height.
- A new game icon: an isometric pixel grass block against a sunset sky.
- The empty hand in first person: the player's right arm with their skin, placed and swung exactly like Beta's empty hand (`HeldItem`, `shaders/hand.gdshader`).
- Statistics and achievements like Beta 1.7.3 (`Stats`), kept across all worlds in `user://stats.cfg`: time played, distances walked, swum, fallen, climbed, flown and ridden by minecart, boat and pig, jumps, items dropped, damage dealt and taken, deaths, mob kills, fish caught, games, and blocks mined and items crafted, used and broken; the 18 Beta achievements without the Nether ones (Taking Inventory, Getting Wood, Benchmarking, Time to Mine!, Hot Topic, Acquire Hardware, Time to Farm!, Bake Bread, The Lie, Getting an Upgrade, Delicious Fish, On A Rail, Time to Strike!, Monster Hunter, Cow Tipper, When Pigs Fly, Sniper Duel, DIAMONDS!), each needing the one before. "Achievement get!" slides in at the top right (`AchievementToast`); the pause menu has Achievements (the map of icons and lines, `AchievementsScreen`) and Statistics (General, Blocks, Items, `StatsScreen`).
- Texture packs (`TexturePacks`): folders in `user://texturepacks/` laid out like `assets/textures`; any file a pack has replaces the game's (blocks, items, mobs, the player's skin, GUI, weather, paintings...). Picked in Options -> Texture Packs (with an optional `pack.txt` description and a button that opens the folder), used from the next start.
- Rails like Beta 1.7.3 (`RailBehavior`): rails with the game's 10 shapes (straight, rising, curved) that join the rails around them when placed (one up or down makes a slope, two at a corner a curve, and the neighbors turn toward the new rail when they have a free end); powered rails (powered by redstone or by powered rails in line up to 8 away; they speed carts up, unpowered they brake); detector rails (power while a minecart is on them). Rails need solid ground.
- Minecarts (`Minecart`) like Beta 1.7.3: following the rails through curves and up and down slopes (0.0078 a tick downhill), pushed on by powered rails (0.06 a tick, or off a wall from standing), at most 0.4 blocks a tick, slowing 0.96 a tick empty and 0.997 ridden; pushed by the player walking into them; right-click to ride (walking forward gets a standing cart going), Shift to get off; broken by a few hits. Chest minecarts (27 slots, their chest window) and furnace minecarts (fed coal or charcoal, they drive themselves for 3600 ticks a piece). Our own cart model and texture.
- Boats (`Boat`): floating half in the water, rowed forward the way the player looks, smashing into 3 planks and 2 sticks when they hit the shore fast, dropped whole when broken by hits. Our own boat model and texture.
- Recipes for rails, powered and detector rails, minecarts, chest and furnace minecarts and boats; models can have bigger textures (`texture_size`).
- Redstone like Beta 1.7.3 (`Redstone`): strong and weak power, powered blocks, wire carrying 15 levels and losing one per block, climbing up and down a block, powering the block it runs into (a dot powers all around), colored by its level; changes spread through a queue and the classic neighbor updates. Redstone dust places wire.
- Redstone parts (`RedstoneComponents`): redstone torches (inverters with a 2-tick delay, light 7, burning out when toggled more than 8 times in 100 ticks), repeaters (1-4 delays of 2 ticks, right-click to change, power only along their line), levers (on floors and walls), stone buttons (20 ticks), stone and wooden pressure plates (players and mobs; wooden ones also dropped items). They fall off without the block holding them.
- Doors (iron ones too), trapdoors, TNT and note blocks react to power.
- Pistons and sticky pistons (`PistonBehavior`): facing any of 6 ways, pushing up to 12 blocks (breaking plants, torches, wire, doors and such in the way, moving the player and mobs along), not obsidian, bedrock or blocks that keep things; sticky ones pull a block back; powered like Beta's, including from next to the block above them. Blocks move at once, without the sliding animation.
- Dispensers (`DispenserBehavior`): 9 slots with their own window, throwing out an item (or shooting an arrow) from a random slot when power arrives.
- Glowing redstone ore (`RedstoneOre`): walking on, hitting or right-clicking redstone ore makes it glow (light 9) and sparkle until a random tick.
- Recipes for redstone torches, repeaters, levers, buttons, pressure plates, pistons, sticky pistons and dispensers; piston sounds; block models can turn a face's texture (`uv_turn`).
- Weather like Beta 1.7.3 (`Weather`): rain and thunder on their own timers (clear for 12000-180000 ticks, rain for 3600-15600), fading in and out; the `doWeatherCycle` game rule and `/weather clear|rain|thunder [seconds]`. Rain (`WeatherEffects`, `shaders/weather.gdshader`) falls around the player down to the first block of each column, one sheet of streaks per column turned toward the player within 6 blocks, splashing where it lands and pattering; it falls as snow in cold biomes (tundra, taiga), where snow piles up on the ground and still water freezes, and not at all in deserts. Rain grays the sky, fog and clouds and takes up to 5/16 of the daylight, a storm as much again. Saved with the world.
- Lightning in storms (`LightningBolt`), now and then near the player: a flickering bolt, a sky flash that lights the world, thunder heard everywhere; on Normal and Hard it sets the struck spot on fire; creatures and the player within 3 blocks take 5 damage and catch fire.
- Rain puts out fire it falls on or next to, and the flames of burning players and mobs; zombies and skeletons don't burn in the rain.
- TNT (gunpowder and sand): lit by flint and steel, by fire burning it, by hitting it (Beta: it lights instead of breaking) and by explosions (a chain reaction on a short fuse); primed TNT (`PrimedTnt`) hops up, falls, smokes, flashes white, swells and explodes after 4 seconds with power 4.
- Drowning like Beta 1.7.3: 300 ticks of air with the eyes under water, shown as bubbles above the food bar; out of air, 2 damage every second with bubbles rising; air comes back at once out of the water. Suffocation: 1 damage at a time with the head inside a solid block.
- Rain, thunder and fuse sounds; rain and snow textures and bubble icons (`tools/make_sounds.py`, `tools/make_item_textures.py`, `tools/make_armor_textures.py`).
- Dyes like the classic game: all 16 (rose red and dandelion yellow from flowers, lapis lazuli from its ore, 4-8 per block, and the lapis block, cocoa beans, cactus green, bone meal, ink sacs) and the mixed ones (orange, purple, cyan, light gray, gray, pink, lime, light blue, magenta); any dye with white wool makes colored wool, and any dye colors a sheep. Shapeless crafting recipes (`Crafting`, `{"shapeless": [...]}`).
- Compass and clock like the classic game: their icons are drawn live into the item atlas (`ItemAnimations`, now one shared texture: `Items.icons_texture()`), so they move in the inventory, in hand and on the ground: the compass needle points to the spawn point with the classic springy swing, the clock's dial (`assets/textures/misc/dial.png`) turns with the time of day behind its window.
- Maps (8 paper around a compass): one pixel per 8 x 8 blocks, 128 x 128, drawn around where the map is first held and filled in around the player while held (`Maps`): the top block's color, lighter or darker with the slope, water darker the deeper. Shown on parchment in the lower middle of the screen with an arrow for the player (`MapView`); kept in the world save.
- Fishing rods (sticks and string, 64 uses): the bobber (`FishingBobber`) flies out on a line, floats on water; now and then (1 in 500 ticks) a fish bites, the bobber dips with a splash, and reeling in then throws a raw fish to the player; a creature it catches on is pulled closer. The rod is held turned around like the game's.
- Paintings (8 sticks around wool): hung on the side of a block, a random picture among those that fit (1x1 to 4x4 blocks, solid wall behind, nothing in front); dropped when hit or when the wall goes. 22 of our own pictures (`assets/textures/art/paintings.png`, drawn by `tools/make_item_textures.py`).
- Saddles: put on a pig, then right-click to ride it (it wanders on its own like Beta's pigs), Shift to get off. The saddle shows on the pig.
- Jukeboxes (planks around a diamond) play music discs "13" and "cat" heard up to 64 blocks away; right-click again or breaking it throws the disc out. The tracks are our own pieces (`tools/make_music.py --records assets/records`).
- Note blocks (planks around redstone): right-click raises the note (25 semitones), left-click plays it, with air above; the block below picks the instrument (harp, bass on wood, bass drum on stone, snare on sand and gravel, clicks on glass); a colored note floats up. Instrument sounds added to `tools/make_sounds.py`.
- Armor like Beta 1.7.3: helmets, chestplates, leggings and boots of leather, chainmail (creative only, like Beta), iron, diamond and gold, crafted with the classic patterns. Every material gives the same points (3, 8, 6, 3; 20 = the whole bar), the material sets how long it lasts; worn armor takes (armor / 25) of every hit (worn-out pieces count less) and wears by the damage taken. Armor slots in the survival inventory accept only the right piece, shift-click puts armor on; worn armor is saved and dropped on death. The armor bar (chestplate icons) shows above the hearts. Items, armor layers and the bar icons drawn by `tools/make_armor_textures.py`; the leather icons are brown like Beta.
- Third-person view (F5, "Toggle Perspective" in Controls): the camera 4 blocks behind the player (closer when a block is in the way) shows the player's body (`PlayerModel`, our own skin) with the worn armor; legs and arms swing with the steps, the head follows the view, the arm swings with the held item, the body bends when sneaking.
- Tools and armor snap with a sound when they break (`random/break`).
- Mobs like the classic game (`Mob`): pigs (porkchops, cooked if they die burning), cows (leather, milk with a bucket), sheep (wool; sheared with shears, dyed, natural colors like Beta), chickens (feathers, lay eggs), squid (ink sacs), wolves (tamed with bones, then follow the player, sit on a click, turn on whoever hurts them), zombies (feathers), skeletons (shoot arrows; bones and arrows), creepers (hiss and explode next to the player; gunpowder), spiders (climb walls, neutral in daylight; string) and slimes (sizes 1, 2 and 4, split when they die; slimeballs). They wander, flee when hurt, chase and hit the player, jump up blocks; zombies and skeletons burn in daylight. Box models from `assets/models/mobs.json` (`MobModels`) with our own 64x64 textures made by `tools/make_mob_textures.py`, drawn by `shaders/mob.gdshader` (lit by the light where they stand, red when hurt); walking, head turning and dying animations.
- Mob spawning (`MobSpawner`) like the classic game, 24..64 blocks from the player: monsters in groups of 1..4 in the dark (light 7 or less, the night sky counts), up to 40; animals on lit grass in daylight, up to 15 (wolves in forests and taiga); squid in water; slimes in slime chunks below y 40. Mobs far away despawn.
- Difficulty setting (Peaceful, Easy, Normal, Hard) in the general options: mob damage scales with it; on Peaceful no monsters spawn (existing ones vanish) and health comes back by itself.
- Combat like Beta 1.7.3: left click on a creature (closer than the targeted block) hits it: fist 1, swords 4/6/8/10 (gold like wood), shovels, pickaxes and axes by tier; knockback; swords wear by 1 per hit, tools by 2 (`Items.attack_damage()`). Right click on a mob uses it (shearing, dyeing, milking, taming, sitting). The player is knocked back by mobs and arrows.
- Bows and arrows (`Arrow`): a bow shoots at once on a click like Beta (an arrow from the inventory, free in creative) and wears out; arrows fly along a falling curve, hurt the first creature they hit (4) and stick in blocks, where the player picks them up. Skeletons shoot them too. Recipes: bow (sticks and string), 4 arrows (flint, stick, feather).
- Explosions (`Explosion`) like the classic game: rays from the middle lose strength with distance and through blocks by blast resistance (stone 30, obsidian 6000, bedrock and liquids stop them); 30% of the destroyed blocks drop; creatures and the player nearby are hurt and thrown back; smoke and a boom.
- Shears (2 iron ingots): shear sheep, cut leaves (which then drop themselves) and cobwebs quickly.
- Dungeons (`DungeonBehavior`): cobblestone rooms with mossy floors underground where caves pass, a mob spawner (zombie, skeleton or spider) and up to two chests with the Beta loot (saddle, iron, bread, wheat, gunpowder, string, bucket, rarely a golden apple, redstone, music discs, cocoa). Spawners wake up when the player is within 16 blocks, smoke and flicker, and spawn up to 4 mobs every 200..799 ticks in the dark. Dungeon chests fill when first seen, opened or broken.
- Items: porkchop, cooked porkchop (smelted), raw and cooked fish, leather, feather, gunpowder, slimeball, ink sac, saddle, arrow, bow, shears, music discs "13" and "cat".
- Mob, explosion and bow sounds added to `tools/make_sounds.py` (say, hurt and death for each mob, creeper fuse, slime squelches, explosion, bow and arrow hit).
- Farming like the classic game (`FarmBehavior`): hoes of 5 materials till grass and dirt into farmland (grass sometimes gives seeds); farmland is wet with water within 4 blocks, dry and bare farmland turns back into dirt, landing on it tramples it; seeds grow into wheat on farmland in 8 stages (twice as fast when wet, needs light); ripe wheat gives wheat and up to 3 seeds; bread from 3 wheat; bone meal (from bones) ripens wheat, grows saplings into trees and sprouts grass and flowers; cake (placed on the floor, 6 slices; milk buckets give their buckets back in the recipe), cookies, golden apples (heal fully). Items: hoes, wheat, bread, bone, bone meal, cake, cookie, cocoa beans, golden apple, milk bucket, egg (bones, milk, eggs and cocoa come with mobs and dungeons).
- The `doHunger` game rule: on (default) hunger like Beta 1.8; off like Beta 1.7.3: no food bar, food is eaten at once and heals right away (apple 4, bread 5, stew 10, golden apple 20, cookie 1, cake slice 3).
- Nature like the classic game (`NatureBehavior`): cactus (stands on sand with nothing solid beside it, grows up to 3 high, pricks for 1 damage, smelts into cactus green; generated in deserts), sugar cane (grows up to 3 high next to water, generated there; makes sugar and paper), brown (glowing 1) and red mushrooms (grow and spread in the dark, generated in caves; mushroom stew from a bowl and both mushrooms gives the bowl back), water lakes (one column in 4), big oaks with branches (one forest tree in 10), and springs: single water and lava sources in cave walls that start flowing when the player comes near. Bowls, sugar, mushroom stew and cactus green items.
- Building blocks like the classic game: stairs (cobblestone, oak, birch, spruce; they give back their material like Beta), slabs (stone, sandstone, wooden, cobblestone; a slab on the same slab makes a double slab), fences joining the fences next to them (`FenceBehavior`, 1.5 blocks high to collide), ladders (climbable: slow fall, Shift holds, walking into them climbs), wooden and iron doors (two halves, the wooden one opens by hand, `DoorBehavior`), trapdoors, signs on floors (16 directions) and walls with 4 lines of text written right after placing (`SignEditScreen`, drawn by `SignTexts`), bricks (clay balls smelt into bricks), clay blocks (generated at the bottom of shallow water), bookshelves (drop 3 books; books from paper), mossy cobblestone, sponges, cobwebs (they hold you; swords break them and get string) and snow layers (lying on land and trees in cold biomes). Recipes for all of them; clay balls, bricks, paper, books, string, door and sign items.
- Block shapes: blocks have their own collision boxes and outline (`BlockType.collision_boxes`, `selection_box`; stairs have two, doors and ladders thin ones, fences 1.5 high), used by the player, entities, dropped items and particles. Block models can be turned by any angle (`BlockModel.register_turned`).
- Door sounds (`tools/make_sounds.py`).
- Background music: three calm piano pieces made from scratch by `tools/make_music.py` (slow chords, a sparse pentatonic melody, a soft pad and reverb; about two minutes each, mp3), played every 10-20 minutes like the classic game.
- More sounds like the classic game: chests creak open and thump shut, flowing water babbles (1 in 64 display ticks), lava bubbles and pops, eerie cave sounds deep in dark caves (mood sounds every 6000-18000 ticks), a sound when the player dies. Added to `tools/make_sounds.py`.
- Torches like the classic game: on the floor or on a wall (leaning 22.5 degrees away from it, `BlockModel` boxes can now be tilted), light 14, falling off without the block holding them, a flame and smoke at the tip; 4 from coal or charcoal over a stick. Flat in the inventory, in hand and dropped.
- Glowstone (light 15, drops 2-4 glowstone dust; 4 dust make the block; nowhere to mine it before the Nether), pumpkins (now generated: a patch in one column of 32) and jack o'lanterns (a pumpkin over a torch, light 15).
- Fire like the classic game (`FireBehavior`): burns on solid blocks and next to burning ones (planks, logs, leaves, wool, tall grass and flowers), ages, spreads around and upward and burns blocks away; hurts and sets on fire the player and entities walking in; glowing, animated like the Beta fire (`FireAnimation`), crackles and smokes. Flint and steel (iron ingot and flint) lights it and wears out after 64 uses; lava sets things around on fire and sends up sparks.
- Display ticks (`VoxelWorld`, `BlockType.display_tick`): like the game, 1000 random blocks around the player per tick show their effects (torch flames, fire smoke, lava pops, burning furnaces).
- Block light like the classic game (`BlockLight`): a second light channel (0..15) next to sky light, computed with it per column on worker threads and kept up to date when blocks change (removal and re-spreading). The mesher averages it per corner like sky light (vertex `CUSTOM0`), the block shaders use the brighter of sky light minus the night's darkness and block light; held, dropped and particle brightness too (`VoxelWorld.brightness_at()`). Lava gives 15, a burning furnace 13. The debug screen shows it.
- Block models (`BlockModel`): blocks drawn as boxes with per-face textures (by default the box's own extent, like the game's models), turned for each facing; the chest is now one. Ready for stairs, slabs, fences, torches, doors.
- Entities (`Entity`, `EntityManager`, `EntityPhysics`): the base for mobs and other moving things: a box colliding with blocks (the same code as the player), gravity, friction, swimming, lava and fire, fall damage, health with invulnerability after a hit, knockback, death, interpolated drawing, saved with the world by type name.
- Sound (`Sounds` autoload): sound groups with random variants, 3D sounds heard up to ~24 blocks and sounds without a place, Sound and Music buses with Music and Sound sliders in Options, a click on every button, background music from `assets/music` every 10-20 minutes. Block sound materials (stone, wood, gravel, grass, sand, cloth, snow, glass): breaking, placing, the hit while breaking, footsteps; item pickup pop, eating and burp, hurt, splash into water, lava hardening fizz. Placeholder sounds generated by `tools/make_sounds.py` (replace any file in `assets/sounds` with a real recording); no music tracks yet.
- `ROADMAP.md`: the plan of everything Minecraft Beta 1.7.3 has that the engine doesn't yet, in stages ordered by dependencies (engine groundwork, light and fire, sound, building blocks, nature, farming, mobs, combat, items, weather, redstone, transport, the Nether, player and interface, multiplayer), as a checklist.
- Chest model and large chests like the modern game (`ChestModel`, `ChestBehavior`): chests are drawn as the game's chest model (a base, a lid and a latch, 14/16 high) with textures from `assets/textures/chest-atlas.png` (the game's chest texture layout, unfolded boxes); its faces become extra layers of the block tile array. A chest placed next to a single chest facing the same way joins it into a large chest (two halves with one long lid and the latch at the seam); opening it shows both halves' 27 slots as one 54-slot window (container4.png, "Large Chest"). Breaking one half leaves a single chest; each half keeps its own items.

- The undead (`Mob.is_undead()`: zombies and skeletons) burn in daylight under the open sky; anything burning is wrapped in the fire block's flames, as big as the creature.
- Held items on models like the game's: skeletons hold a bow, and in third person the player holds what is in their hand (tools pointing forward from the fist, the bow by its grip, other items and blocks small in the hand) (`MobModels.held_item()`).
- A little mob turns inside every mob spawner, like the game's (`SpawnerMobView`): the spawner's mob at 7/16 of its size, tilted 30 degrees, spinning fast while the player is near (faster as the next spawn nears).
- Creature and player animations in the style of Beta 1.7.3's models (`MobAnimation`): idle arm sway and a little head nod, idle glances around (and looking at the player only for a while, like the game's); the arm raised a little when holding something; walking with the game's leg and arm swing (zombies and skeletons keep their arms ahead and sway them); Beta's sneaking pose for the player (body bent forward, arms along, legs stepped back, head down a pixel); jumping (a leg ahead, front legs ahead on four-legged animals) and falling (arms spread, legs apart); slimes stretch when they jump and squash when they land like the game's; a short flinch when hurt; the player in third person also falls over when dead, like the mobs; a puff of smoke when a dead creature is gone; the player lies in the bed asleep (seen in third person).
- Double doors: a door placed next to another one gets its hinges on the other side (like Beta: it is an open door turned a quarter), so the two meet in the middle; otherwise the hinges go to the side with more solid blocks.

### Changed
- Much faster world streaming and smoother frames while moving (render distance 12: the whole area loads in about 31 s instead of 59; flying on at 11 blocks a second, 93% of the area keeps up instead of 59-68%, and frames over 33 ms went from 115 to about 5 in 20 seconds):
  - chunks deep under the ground far from the player (more than 4 columns away, below the lowest surface around) get no mesh until the player comes near (they were most of the meshing work and nobody sees them); the isometric view still builds them all;
  - light: a block change only relights when what the block lets through or gives off changed (flowing water changing level, lava next to lava no longer do); a brighter source only spreads light; spreading is a queue worked off a little each frame; changes far from the player (more than 3 columns) relight whole columns on worker threads instead of cell by cell on the main thread;
  - block light looks for its sources only in chunks that have glowing blocks (`ChunkData.glow_count`): a column's light job is about a third faster;
  - generation: looking for dungeon spots checks the room's openings first (it was 18 of 47 ms a column);
  - workers: generation and light may use all but two slots with one kept for meshes (and one for them when meshes flood in), every core but one works behind the loading screen;
  - the mesh queue is only sorted when the player changes column; columns that become ready join it directly; the columns to load are listed ring by ring without sorting; columns unloading behind the player are saved on a worker thread;
  - scheduled ticks get 3 ms and random ticks 2 ms a tick; only changes within 3 columns of the player are meshed before everything else.
- The loading screen is like the classic game's: the dark dirt background, the world's name, the current stage and a thin grey bar with a green fill and the percentage under it, following the real progress (each column generated, lit and built). Green pixel sparks fly out of the bar's growing end (livelier while it moves fast) and burst out along it when it is full, then the screen fades into the game. The floating island is gone (with `VoxelWorld.column_states` and `loading_background.gdshader`).
- The Create New World screen has less text: no game mode description or "Will be saved in:", the seed hint is inside the empty seed field.
- Arrows use the game's arrow model and the new `textures/entity/arrow.png` (crossed pictures and the back, lit where they are); the fishing bobber is the game's picture (`textures/entity/fishing_bobber.png`) facing the camera; minecarts use the game's minecart model with the new `minecart.png`; boats use Beta's boat model (a bottom and four sides) with a texture in its layout made from oak planks.
- Flowing water and lava tops show the flowing texture turned along the flow (worked out from the levels around, like the game's flow vector), twice as big like Beta; still liquid keeps the still texture.
- The Create New World screen is laid out like Beta 1.7.3's: one column in the middle of the dirt background, the world name with "Will be saved in:", the seed with its hint, the game mode with its description and the world type, and Create New World / Cancel one under the other.
- The health bar takes its hearts, armor and air bubbles from the game's `textures/icons.png` (the hurt heart outline too).
- Block variants show their kind's name (fire, piston head) instead of a numbered one; Russian names for the mobs, carved pumpkins, double slabs, springs, the piston head and the new screen texts.
- The Classic shader pack looks like Beta 1.7.3: light levels, smooth lighting corners (0.4 / 0.6 / 0.8 of the light) and face shading (sides 0.8 / 0.6, bottom 0.5) are worked out on the textures' sRGB colors like the game and only then made linear, so corners are deep, sides clearly darker and torch-lit rooms moody; no filmic tone mapping with Classic (it flattened the contrast). Creatures, items and particles use the same curve. The Brightness setting now works like the modern game's: Moody is the classic game, higher values lift the dark light levels without washing out the lit ones (Dynamic Lighting keeps it as the exposure).
- The health bar is Beta's: hearts on the left, the armor bar on the right (filled from the right), air bubbles above the hearts.
- Faster chunk work for the taller world: chunks of only air are never meshed (`ChunkData.air_count`), generation, lighting and meshing share the worker threads (generation and light at most half of them each), the mesh queue is sorted at most 4 times a second while the world streams in, and chunks with changed blocks are meshed first without waiting for it; random ticks find their chunks through per-column lists. At render distance 12, moving and turning gives 0-1 frames over 33 ms (16 right after the world grew, 0 before).
- Monsters spawn at heights up to the ground of their column (not in the empty sky); slimes below y 104 (40 above the old bottom).
- The creative inventory uses `container5.png`: an 8 x 9 catalog of every block and item with a scrollbar (drag it or click the track; the wheel scrolls too) and the hotbar below.
- Aiming goes through the empty part of blocks that aren't full (snow layers, slabs, torches, plants, doors...) to the block behind, like the game's: the ray checks the block's own boxes.
- The block outline is sharper: lines about 2 pixels wide at any distance (`shaders/outline.gdshader`), around each box of the block (both steps of stairs); plants and torches are picked by narrower boxes like the game's.
- Achievements and statistics belong to each world (kept in its save) instead of to all worlds; 11 achievements of our own were added (Playing with Fire, Kaboom!, Engineer, Musician, DJ, Fisherman, Art Lover, Good Night, Sailor, Best Friend, Treasure Hunter), shown in blue on the map.
- The isometric camera's settings moved from the options into the isometric view itself (F6): a panel on the right changes the angle, facing, zoom, clouds, fog, screenshot size and background as you click, with a screenshot button; the mouse is free while it is open.
- The wolf follows the game's model and texture layout and uses the new `pale_wolf` skin (the generated one is gone); tame wolves wear a red collar (`wolf_collar`, drawn over the neck), hold their tail high (lower when hurt, the classic health gauge) and have 20 health like Beta.
- Mob models follow the game's own boxes and texture layout (`assets/models/mobs.json`), so the game's skins fit: 64 x 32 skins work next to 64 x 64 ones, left limbs can use the right ones' texture mirrored, the cow's and sheep's bodies lie along the box like the game's, horns, the udder and the fleece move with their parts. The sheep's fleece is now made of a head, body and leg pieces. New skins for the zombie, skeleton, creeper, spider, cow, sheep, squid, the player and the armor of every material (the leather armor tinted brown like Beta); pigs, chickens, slimes, wolves, the fleece and the leggings layer keep the generated ones. `tools/make_mob_textures.py` and `tools/make_armor_textures.py` no longer overwrite textures that are already there.
- Block ids are 32-bit (`ChunkData.blocks` is a `PackedInt32Array`): up to 65535 block states instead of 256, every state its own id. Older saves (one byte per block) are converted on load and written back; item ids moved to 32768 and up (`Items.FIRST_ITEM`), older saved inventories and dropped items are renumbered (`Items.from_save()`).
- Player collision lives in `EntityPhysics`, shared with entities.

### Fixed
- Frame drops while flying a long way into new land: worker jobs (generation, light, meshes) use half the cores so the main thread and the renderer keep one (with 8 of 10 they took the fast cores and frames stalled), scheduled ticks stop after 5 ms a tick (the rest waits; flooding liquids relight a lot), a slow game runs at most 3 ticks a frame to catch up (10 made each frame slower still), and the scheduled tick count no longer grows when ticks wait. In a 25-second flight at render distance 12: 0-1 frames over 33 ms.
- Worlds converted to the 256 high world get no holes under their old lava and water: the old bedrock floor turns to stone and the deep caves stay below it.
- Arrows: the block they are stuck in can be taken away and they fall; they stay for two minutes (was one); they take their light from the shaft, not the tip inside the block (that side was dark).
- A spider in a spawner stands on its legs (they stuck out flat).
- The Options screen's buttons are in even pairs (World Settings was alone with gaps around it); in a world it pairs with Shaders.
- The loading screen has the title screen's shade (`gui/titleBlur.png`) and no longer shows the world's name (only the stage, the bar and the percentage).
- The cactus is drawn like the game's: the top and bottom fill the block and each side is the whole texture moved a pixel in, so the spines stick out at the edges (it was a squeezed, uneven smaller box).
- Water (flowing or a source) under a solid block is drawn again: its surface lies lower than the block above, so it can be seen.
- Ice next to water shows all its side faces (they were cut down to a strip above the surface).
- The skeleton's spine and other thin parts are seen from both sides (the mob shader draws back faces).
- Block icons in the inventory could stay empty (rendered once before the viewport was ready): they render for a few frames now.
- Stutters while moving and turning (frames of 50-100 ms at render distance 12): random block ticks only reach 8 columns around the player like the game's (they ran over the whole loaded world) and spread over ticks when a tick runs long; display ticks pick their blocks straight from the 27 chunks around; the cave culling search runs on a worker thread and only changes the chunks that change; chunk meshes are built on the worker threads too, and at most ~4 ms of them are put in place a frame; faster block and light lookups. The debug screen shows where each frame's and tick's time goes.
- Eating: the food comes up in front of the mouth, turned toward the face, and bobs like the game's (it stood on edge at the side); the crumbs are smaller and below the middle of the view; no swing after eating (only Beta's instant eating swings).
- Squid swim under the water in pushes, mostly level, and lean into the way they go (they stood upright and bobbed above the surface).
- The pig lost its body with the new skin: its model follows the game's layout now; the saddle is the game's overlay (`saddle_pig`); the chicken follows the game's layout for its new skin; the slime's outer jelly is see-through (`mob_translucent.gdshader`).
- Flowing water's sides show the top of the texture cut off at the surface instead of squeezed.
- Items float at the water's real surface (flowing water is lower) instead of at the top of its block.
- Jumping on farmland no longer sinks you into the ground: like the game, farmland is drawn 15/16 high but solid all the way up.
- Doors: the back of the door is mirrored like the game's, so the hinges are on the same edge from both sides and the door swings open on the hinge side.
- In the isometric view, fog no longer hides everything (it is measured from the far-away camera, without water or lava fog) and the hand no longer shows through walls.
- Esc no longer pauses the game while the world is loading.
- F1 hides the HUD like the game (crosshair, hotbar, health, chat, debug screen, the hand) while the inventory, menus and other windows still show.
- Spider legs slope down to the ground like the game's (front and back pairs at 45 degrees, the middle ones flatter); they pointed up.

### Removed
- The Low / Medium / High presets in Video Settings (one of them switched the shader pack to Dynamic Lighting); shader packs are only switched by hand in Shaders.
- Sprinting and hunger, which Beta 1.7.3 didn't have: no sprint key or double-tap, no food bar, saturation or exhaustion, no `doHunger` and `naturalRegeneration` game rules (`FoodStats` is gone). Food is eaten at once with a click and heals right away (apple 4, bread 5, stew 10, golden apple 20, cookie 1, a slice of cake 3), only when hurt; the held-down eating and its hand animation are gone too.
- The hand-drawn chest tiles in the block atlas and `tools/make_chest_tiles.py` (replaced by the chest model).

## [0.0.2] - 2026-11-10

### Added
- Saplings (oak, birch, spruce) like the classic game: dropped by leaves, planted on grass or dirt; with enough light (9+) they grow into a tree of their kind after a while (1 in 14 random ticks, `SaplingBehavior`), when there is room.
- Plants like the classic game: tall grass and ferns (colored by the climate), dandelions, roses and dead bushes, drawn as two crossed squares. Generated per column like Beta 1.7.3: patches of grass by biome (plains and rainforests 10, forests 2, taiga, shrubland, savanna and swamps 1; rainforests mostly ferns), two patches of dandelions and sometimes roses everywhere, dead bushes in deserts. They break at once, tall grass and ferns sometimes drop seeds, they break when their ground goes, placed blocks and flowing liquids replace them (water washes them away, lava burns them) and they are placed only on grass / dirt (dead bushes on sand). Inventory icons show their picture.
- Leaf decay like the classic game (`LeafBehavior`): tree leaves need a log within 4 blocks through leaves; when something next to them changes they check again after 1-10 s and fall apart without one, dropping what they give (oak leaves sometimes an apple). A cut tree loses its crown bit by bit. Leaves placed by the player never decay (`*_leaves_placed` variants).
- Lava like the classic game: still and flowing lava (flows 3 blocks, slower than water: a step every 1.5 s), glowing at full brightness day and night (also in Dynamic Lighting), animated like the Beta lava (`LavaAnimation`). Generated in caves below y = 10 and in lava lakes (one column in 8, mostly underground). Lava touching water hardens: a source into obsidian, flowing lava into cobblestone; lava falling onto water turns it into stone. Buckets scoop lava (lava bucket: 1000 s of furnace fuel, the bucket stays) and pour it.
- Lava and the player: inside it the player moves slowly, takes 4 damage at a time and catches fire for 15 s (1 damage per second, flames on the screen); water puts the fire out; the view inside lava is a thick glowing fog. Dropped items burn up in lava.
- Water currents push the player and dropped items like the classic game (the flow of the water blocks around them, 0.014 per tick).
- Items like the classic game (`scripts/items/`): besides blocks there are items with icons from `items.png` — sticks, coal, charcoal, iron and gold ingots, diamonds, redstone, flint, snowballs, apples, buckets, water buckets, the bed and wooden / stone / iron / diamond / golden swords, shovels, pickaxes and axes. Flat items are drawn in the hand as a 3D extruded picture, in slots as their icon; tools show a durability bar and wear out. Inventories keep each stack's damage; saves keep it too.
- Drops and dropped items like the classic game (`scripts/entities/item_entities.gd`): breaking a block drops what it gives as an item that spins (blocks) or faces the camera (items), bobs, falls, floats in water, merges with equal stacks nearby and is picked up when the player walks close (it flies to the player). Q throws one item (Ctrl+Q the stack), clicking outside an inventory window throws the held stack, dying scatters the inventory (unless keepInventory), items vanish after 5 minutes and are saved with the world. Drops follow the classic rules: stone gives cobblestone, coal / diamond / redstone ore their items, gravel sometimes flint, snow 4 snowballs, oak leaves rarely an apple, glass and ice nothing.
- Tools and harvesting like the classic game: breaking speed = the right tool's speed (wood 2, stone 4, iron 6, diamond 8, gold 12) / hardness; stone and ores need a pickaxe (iron and lapis ore a stone one, gold, diamond and redstone ore an iron one, obsidian a diamond one), otherwise they break 3x slower and drop nothing. Shovels for dirt, grass, sand, gravel and snow, axes for wood.
- Crafting table (RMB): a 3x3 crafting grid (container1.png). Recipes, also mirrored: sticks, chest, furnace, bed (any wool), bucket, all tools, iron / gold / diamond blocks and back, sandstone, snow from snowballs.
- Chests (RMB): 27 slots each (container3.png), facing the player when placed; what they hold is saved with the world and spills out when the chest is broken. Chest textures drawn by `tools/make_chest_tiles.py` into free atlas tiles.
- Furnaces (RMB, container2.png) like the classic game: input, fuel and output; fuel burns (coal / charcoal 80 s, logs and planks 15 s, sticks 5 s, wooden tools 10 s), every item takes 10 s; the fire and the arrow show the progress; a burning furnace shows its fire on the front and gives off smoke and flames. Recipes: ores to ingots / items, sand to glass, cobblestone to stone, logs to charcoal. Furnaces keep working while the window is closed and are saved with the world (block entities).
- Flowing water like the classic game (`WaterBehavior`): levels 0 (source) .. 7 and falling water; it falls into air, otherwise spreads up to 7 blocks toward the nearest drop within 4 blocks, dries up without a source and two sources next to it make a new one. Its surface slopes down from the source (each corner as high as the water around it). Buckets scoop up sources and pour them out.
- Beds (RMB): two blocks 9/16 high, placed with the head away from the player; sleeping is possible only at night, the screen fades out for 5 seconds and the night is skipped to the morning; the bed becomes the respawn point. Breaking one half removes the other.
- Particles like the classic game (`scripts/entities/block_particles.gd`, `shaders/particle.gdshader`): a broken block bursts into 4 x 4 x 4 bits of its texture, a block being broken chips bits off the face, eating sends crumbs of the food, a burning furnace smokes. Bits fall, bounce on blocks and take the light where they are.
- Eating (hold RMB with food for 1.6 s, like the classic game): the food bobs at the mouth, crumbs fly, then it restores food and saturation.
- Partial-height blocks (`BlockType.height`, the bed): drawn lower with the matching part of their textures, collide at their height and never hide neighbor faces. Oriented textures per face (`BlockType.uv_modes`) and cull groups (`BlockType.cull_group`).
- Random Texture Rotation (Video Settings → Quality, on by default), like the modern game's random block variants, fixed per block position so large areas of one block no longer show a repeating grid pattern: dirt, grass and sand are turned by a random multiple of 90 degrees around the vertical axis (the top texture turns, the sides stay the same); stone and bedrock are only mirrored and / or turned by 180 degrees, so their grain keeps its direction; gravel and snow are not changed (`BlockType.random_rotation`, `ChunkMesher.build(..., origin)`).
- Grass and foliage colors from the climate of every block column, like the classic game's color maps (bluish green in the cold, yellow-green when hot and dry, lush green when hot and wet): colors change smoothly across biomes instead of jumping at biome borders (`BlockType.biome_tint`, `WorldGenerator.column_colors()`).
- Languages like the classic game (`scripts/core/lang.gd`, `assets/lang/*.lang`): English (default) and Russian, chosen in Options → Language... and applied at once. A language file maps each English text to its translation (`Video Settings...=Настройки графики...`); labels and buttons translate themselves through Godot's TranslationServer, texts built in code use `Lang.t()`. Menus, settings and their values, key bindings, block names, inventory, loading, death and title screens, screenshot and chat messages are translated; the debug screen stays in English like the classic game. A new language = one .lang file and a line in `Lang.LANGUAGES`.
- Options laid out like the modern classic game: FOV and World Settings on top, then Video Settings, Controls, Language and Isometric Camera.
- Controls laid out like the modern classic game: mouse options on top, key bindings grouped by category, each row with its key and a Reset button; Reset Keys and Done at the bottom.
- Video Settings: Fog and Fog Distance (where the fog starts), and the Animations (animated water, star twinkle, cloud movement, hand animation, with All ON / All OFF) and Other (debug screen, reduce FPS in background) sections.
- Isometric camera (**F6**, `scripts/render/isometric_camera.gd`), like the old game's isometric view: an orthographic camera looking down at the player from a diagonal; **Z** / **X** turn it by 90 degrees, the mouse wheel zooms; the crosshair and the block in hand are hidden.
- Isometric screenshots (**F7**, `scripts/render/screenshots.gd`): the whole drawn area rendered off-screen from the isometric angle at up to 8192 px, without GUI, fog or clouds; the edge chunks are re-meshed as if nothing were beyond them, so the sides are solid cuts through the ground (stone, ores, caves) like a diorama. About 2.5 s at 2048 px.
- Screenshots (**F2**) and Hide GUI (**F1**) like the classic game; pictures are saved to `user://screenshots/` and the chat says the file name.
- Isometric Camera settings (Options → Isometric Camera...): view angle (classic 30°, true isometric 35°, steep 45°), facing, zoom, clouds and fog in the isometric view, screenshot size (2048 / 4096 / 8192 px) and background (sky / transparent). New key bindings in a Camera category.
- Advanced cave culling like the modern game (Sodium / vanilla 1.18+): while meshing, every chunk records which of its faces are connected through non-opaque cells (`ChunkMesher.connectivity`); a breadth-first walk from the camera's chunk through connected faces, never turning back, hides the chunks that can't be seen (caves behind rock, the ground below). Example: 519 of 1029 chunks hidden, 28% fewer triangles above ground; much more underground. Cave Culling setting; the debug screen shows the hidden chunks.
- Chunks in front of the camera are built first (the ones behind count as three times farther), like the modern game.
- Reduce FPS in Background (like the Dynamic FPS mod): 15 FPS while the window is not focused, 1 FPS while minimized.
- Video Settings laid out like the classic game: Graphics (Fast / Fancy), Render Distance, Smooth Lighting (OFF / Minimum / Maximum), Max Framerate, Use VSync, View Bobbing, GUI Scale, Brightness, Clouds (OFF / Fast / Fancy), Fullscreen; sections Details (fog, stars, sun & moon, vignette, debug screen), Quality (anti-aliasing, anisotropic filtering, animated water), Performance (render scale, cave culling, chunk updates per frame, reduce FPS in background) and Shaders; presets Low (weak computers), Medium and High (powerful computers) that set these and the shader pack.
- Fast graphics: leaves are drawn opaque with their fast textures (fewer faces, no cutout), like the classic game; fast clouds are flat. Smooth Lighting Minimum keeps smooth light without ambient occlusion.
- Shader packs (Options → Shaders..., `scripts/render/`): the lighting style is a pack that can be switched at once in game.
  - **Classic** (the default): lighting like the original game, with no real-time sun light or shadows; light is baked into the blocks (smooth sky light and AO), faces are shaded by side (top 1.0, north/south 0.8, east/west 0.6, bottom 0.5) and sky-lit blocks darken at night (`shaders/block_classic_*.gdshader`). The fastest.
  - **Dynamic Lighting**: the engine's real-time sun and moon light with shadows.
  - Pack options built from `Setting`s (toggles, choices, sliders) and applied live: Classic — face shading, night brightness; Dynamic Lighting — shadows (Off / Low / High), sun strength, ambient light, water shine, glow (bloom); both — saturation, contrast.
  - New Pack copies the selected pack into a pack of your own (renamable, deletable), saved as a text file in `user://shaderpacks/` (Open Folder); changes to the built-in packs are kept as overrides.
  - `ShaderPacks` autoload (packs, selection), `ShaderPack` (base + option values), `ShaderPackApplier` (sun, shadows, environment), `BlockMaterials.apply_pack()` / `set_parameter()`. The debug screen shows the pack.
- Animated water like the classic Beta game (`scripts/render/water_animation.gd`): the still water (tops) and flowing water (sides) textures are small simulations of ripple energy, stepped 20 times per second and written into the block tile array (brighter, greener and more opaque where the energy is high; the flowing one slides down).
- Title screen sky (`shaders/title_sky.gdshader`): a calm evening in the style of the loading screen, deep blue fading to a warm horizon glow, twinkling stars; warm light and evening clouds over the island.
- Health and hunger like the classic game (survival): 20 health (10 hearts) and 20 food (10 drumsticks) with hidden saturation. Fall damage (1 per block beyond 3, not into water or while flying), the void below y = -64 (also in creative). After a hit 20 ticks of invulnerability in which only a stronger hit counts (the difference); hurt tilt of the view and blinking hearts. Exhaustion from sprinting, walking, swimming, jumping, breaking blocks and damage uses up saturation and food (`scripts/player/food_stats.gd`); food 18+ heals 1 every 4 s, food 0 starves down to half a heart, food 6 or less stops sprinting.
- Hearts and drumsticks above the hotbar (`scripts/ui/status_bars.gd`, the hearts / hunger textures), jittering at low health / no saturation; hidden in creative.
- Death like the classic game: the view falls over sideways, the screen turns red, "You died!" with the score, then Respawn (world spawn, full health and food) and Title Screen (`scripts/ui/death_screen.gd`). Items are lost on death (no item entities yet) unless the new `keepInventory` game rule is on; new `naturalRegeneration` game rule.
- Health and food are saved with the player; the debug screen shows them.
- The world behind the in-game menu and inventories is slightly blurred (like the title panorama).
- Title screen (`scenes/title.tscn`, now the main scene): a live panorama of a freshly generated 48x48 piece of world (cut out like a diorama, lit, under the real sky and 3D clouds) with the camera slowly circling it, generated on worker threads and faded in; the logo, a pulsing splash text, Singleplayer / Options / Quit buttons, version and credits. On the first start the studio logo is shown (click or any key skips it).
- World saves (`scripts/save/world_save.gd`): each world is a folder in `user://saves/` with `level.cfg` (name, seed, world type, game mode, dates, time of day, game rules, player position, look direction, flying, inventory and selected slot) and the columns the player changed (zstd-compressed; untouched terrain is generated again from the seed). Changed columns are written when they unload, on autosave every 45 s, on Save and Quit and when the window closes.
- Select World screen: saved worlds, most recently played first, with folder, last played date, game mode and seed; click selects, double click plays; Play Selected World, Create New World, Delete (with confirmation), Cancel.
- Create New World screen: world name, seed (a number, any text hashed, or empty for random), game mode (survival / creative) and world type (default / random blocks).
- Loading screen (`scripts/ui/loading_screen.gd`): a floating island turns in the middle of a starry gradient and builds itself as the world loads, its block columns dropping into place in a spiral with a bounce and a tree growing last; the phase (generating terrain, lighting, building terrain), a progress bar and the percentage follow the real progress of the columns around the player. Fades out into the game.
- Game Menu: Back to Game and Save and Quit to Title.
- `scripts/game.gd` (game scene controller), `VoxelWorld.loading_progress()`, `save_columns()`, `save_state()`; `Player.save_state()` / `load_state()`; text fields in the UI theme; `MenuScreen.add_bottom_row()`; `ConfirmScreen`.
- 3D clouds like the classic fancy clouds (`scripts/render/clouds.gd`): 12x12-block cells, 4 blocks thick, at y = 108, drifting east with the game ticks, shaded per face and colored by the time of day. The mesh is built once and follows the camera; the shader reads a repeating 256x256 pattern and hides empty cells and inner faces, so clouds cost no CPU time per frame.
- Atmosphere (`scripts/render/atmosphere.gd`): fog colored like the sky at the horizon (dark at night, orange when looking toward a rising or setting sun); dense blue fog and a blue tint under water; vignette that gets stronger in the dark (new Video setting).
- Block in hand (`scripts/player/held_item.gd`): the selected block in the bottom right of the view like the classic game, with the swing arc when breaking or placing, the lower-and-raise animation when the item changes, and the light at the player. Drawn over the world so it never sinks into walls.
- Water like the classic game: the surface is 2 pixels below the block top unless more water is above, and the water texture shimmers in slow waves (per texture pixel, continuous across blocks).
- `Player.selected_slot`, `held_block()`, `swing()`; `ChunkMesher.to_mesh()` / `block_mesh()` shared by chunks, falling blocks, icons, cracks and the block in hand.
- Player (`scripts/player/player.gd`) with the movement of the classic game, replacing the free-flying camera: physics in fixed steps of 20 per second with the classic constants (blocks per tick), interpolated for rendering; a 0.6 x 1.8 box colliding with blocks axis by axis (Y, X, Z), eyes at 1.62. Walking 4.32 m/s, sprinting 5.66 m/s (**Ctrl** or double-tap **W**, sprint-jumps push forward, FOV widens), jump height 1.25 blocks, ground friction (ice is slippery), stepping up to 0.6 blocks, sneaking (**Shift**: x0.3 speed, eyes lower, no walking off edges), swimming (Space swims up, climbing out onto the shore), creative flying (double-tap **Space**, Space / Shift up and down, ends on landing), view bobbing (new Video setting).
- Game modes, survival and creative, and `/gamemode <survival|creative>` (also `s`/`c`, `0`/`1`). The game starts in creative.
- Inventory (`scripts/player/inventory.gd`): 36 slots (hotbar + main), stacks of up to 64. The hotbar shows the first 9 slots with item counts.
- Inventory windows on **E** (`scripts/ui/inventory/`), built on the container textures: survival with armor slots (empty for now), a 2x2 crafting grid and result, the main inventory and the hotbar; creative with every block in a scrollable 9x6 catalog. Classic mouse handling: pick up / put down / swap stacks, right click for half / one, shift-click to move between hotbar and inventory, number keys over a slot to swap with the hotbar, tooltips with block names. Closing returns the held stack and the crafting grid to the inventory.
- Crafting (`scripts/player/crafting.gd`): shaped recipes matched anywhere in the grid; logs -> 4 planks, 2x2 planks -> crafting table, 2x2 sand -> sandstone.
- Survival block breaking: hold LMB, time = hardness x 1.5 s by hand (new `BlockType.hardness`, classic values; bedrock and water can't be broken), crack stages from the atlas drawn over the block; the block (or its drop: stone -> cobblestone, grass -> dirt, glass / leaves / ice -> nothing) goes into the inventory. Placing uses up one item. Creative: instant breaking and placing without using items. Holding the buttons repeats (5 / 4 ticks) like the classic game.
- `BlockType.collides`, `slipperiness`, `drop`; `Blocks.collides_table`, `Blocks.drop_of()`, `Blocks.display_name()`.
- Debug screen: game mode, horizontal speed and player state (on ground, flying, sprinting, sneaking, in water); XYZ is now the feet position.
- Sky light like the classic game (`scripts/voxel/sky_light.gd`): every block has a light level 0..15; full light comes straight down from the sky (leaves take 1, water and ice 2, solid blocks stop it), then spreads sideways and down into overhangs and caves, losing at least 1 per block. A column is lit on a worker thread from the 3x3 columns around it, so there are no seams at column borders; cells above the heightmap are never stored or visited, so it stays cheap.
- Re-lighting on block changes: light removal and re-spreading from the changed block (the classic algorithm); only chunks whose light changed are re-meshed.
- Smooth lighting in the mesher: each vertex gets the average light of the up to 4 clear cells around the corner, mapped with the classic light curve (level 0 keeps 5%) and combined with voxel AO. With Smooth Lighting off, faces get flat light.
- `BlockType.light_opacity`, per-chunk light arrays and per-column heightmaps. Debug screen: sky light at the player and at the targeted face, lighting jobs.
- Endless world (`VoxelWorld`): columns of 8 chunks (128 blocks high) are generated around the player on worker threads, nearest first, meshed once their neighbor columns exist and unloaded when far away; `Render Distance` setting (2-16 chunks, default 6) with fog starting at 60% of it like the classic game. Spawn is searched on land.
- Beta 1.7.3 style world generator (`scripts/worldgen/beta_generator.gd`, own implementation of the same approach): 3D density terrain from limit / main / depth / scale noises with overhangs, sea level 64; biomes from temperature and humidity with the classic table (tundra, taiga, swampland, forest, seasonal forest, rainforest, savanna, shrubland, plains, desert); grass / dirt surface, sand and gravel beaches, sandstone, uneven bedrock; worm caves and rooms crossing columns; ore veins and dirt / gravel pockets at the classic heights; oak, birch, spruce and pine trees by biome; ice on cold water. Deterministic per seed.
- `WorldGenerator` base class for column generators; the random-blocks debug world is one of them.
- Blocks: snowy grass, snow, ice.
- Debug screen: biome, loaded / visible chunks, columns, render distance, generation and meshing jobs.
- Falling block entities (`scripts/entities/falling_blocks.gd`): sand and gravel with nothing below turn into entities that accelerate down smoothly (classic physics per tick: gravity 0.04, drag 0.98) and become blocks again where they land; blocks landing in the same column in the same tick stack up. Simulated in game ticks on packed arrays (no node per entity), rendered with one MultiMesh per block type using the chunk block mesh and materials, positions interpolated between ticks. Tested with 256 blocks falling at once: under 1 ms per tick.
- Debug screen shows the number of falling block entities.
- Hotbar (`scripts/ui/hotbar.gd`) drawn with hotbar.png / hotbarSelector.png: 9 slots with isometric block icons generated from the atlas (`BlockIcons`: top, south and east faces with shading, biome tints and overlays), selection with **1-9** or the mouse wheel, block name shown above for 2 s.
- Crosshair (`scripts/ui/crosshair.gd`, cursor.png) that inverts the colors behind it.
- Block interaction (`scripts/player/block_interaction.gd`) with the mouse captured: **LMB** breaks, **RMB** places the selected block, **MMB** picks the targeted block into the hotbar; reach 5 blocks, outline around the targeted block. Edits go through `set_block`, so block updates apply (sand falls, grass reacts).
- `VoxelWorld.raycast()`: voxel traversal (Amanatides & Woo) returning the hit block, face and distance; air and water are passed through.
- Debug screen (`scripts/ui/debug_screen.gd`) in the style of the classic F3 screen, toggled with **F3**: version, FPS, render stats, ticks, chunks and faces, XYZ / block / chunk position, facing with yaw and pitch, world, clock, sun and light on the left; renderer, memory, CPU, GPU, display, render settings and the targeted block (name, id, layer, face, distance, tick behaviors) on the right. Each line on a translucent gray background.
- `application/config/version` in project.godot (shown on the debug screen).
- In-game menu (`scripts/ui/menu/`): **Esc** pauses the game (ticks stop) and opens a minimal Game Menu with one button, Options; Esc / Done go back. Options: FOV, Video Settings, Controls, World Settings. Styled like the classic game with the GUI widget textures (buttons, sliders) and the pixel font with shadows (`UiTheme`, shared with the chat).
- Settings system (`scripts/settings/`): every option is a `Setting` (toggle, choice or range) registered by category in the `Settings` autoload and saved to `user://settings.cfg`; menus build widgets from settings automatically. Video: render scale, max framerate, VSync, fullscreen, GUI scale, anti-aliasing, shadows, smooth lighting (voxel AO), clouds, fog, brightness, debug info. Controls: mouse sensitivity, invert mouse.
- Key bindings (`KeyBindings`): every action can be rebound on the Controls screen (click, press a key, Esc cancels), conflicts are shown in red, Reset Keys restores the defaults; saved with the settings.
- World Settings screen built from the `GameRules` registry (doDaylightCycle, randomTickSpeed) plus generator, seed and world regeneration.
- Command system modeled on Brigadier (`scripts/commands/`): commands are trees of literals and typed arguments (`CommandNode`); `CommandDispatcher` parses and runs them, suggests completions for the text being typed and builds usage strings and `/help` from the same tree, so every command is described once. Errors are reported like the classic game (`...<--[HERE]`).
- Reusable argument types with their own parsing and suggestions (`scripts/commands/arguments/`): integer, float, bool, choice (fixed or dynamic list), block (from the registry), position with `~` relative coordinates, time (`100`, `5s`, `2d`), message (rest of the line).
- Commands: `/help [command]`, `/time set|add|query`, `/tick query|freeze|unfreeze|step|rate`, `/gamerule <rule> [value]` (generated from the `GameRules` registry: `doDaylightCycle`, `randomTickSpeed`), `/setblock`, `/fill`, `/tp`, `/seed`, `/say`.
- Chat (`scripts/ui/chat.gd`) in the Minecraft Rus font: **T** opens it, **/** opens it with a command; suggestion list above the current word (Up/Down select, Tab inserts), the rest of the chosen suggestion in gray after the cursor, expected argument or the parse error shown while typing, sent-message history on Up/Down, Page Up/Down scroll, messages fade out 10 s after closing.
- `GameInput` lock: camera and sun controls ignore keys and clicks while the chat is open.
- Game tick system (`scripts/core/tick_loop.gd`, autoload `TickLoop`): all game logic runs at a fixed 20 ticks per second independent of FPS, in ordered phases (world, entities, late); catch-up capped at 10 ticks per frame; `alpha` for interpolating visuals between ticks; measured TPS and ms per tick in the HUD; **P** freezes ticks, **.** steps one tick while frozen.
- World clock in ticks (`scripts/voxel/world_clock.gd`): `game_time` (only grows) and `day_time` (24000 ticks per day, can be moved), `daylight_cycle` switch.
- World ticks in `VoxelWorld`: scheduled block ticks (merged per position, capped per tick), random ticks (`random_tick_speed` = 3 per chunk per tick) and block updates sent to a changed block and its 6 neighbors; `get_block` / `set_block` in world coordinates.
- Block tick handlers in `BlockType` (`random_tick`, `scheduled_tick`, `on_update`) and the first behaviors (`scripts/voxel/behaviors/`): grass spreads onto uncovered dirt and turns into dirt under opaque blocks; sand and gravel fall (now as smooth falling entities, see above).
- Changed chunks are re-meshed on worker threads (`WorkerThreadPool`) from a snapshot and swapped in when ready, so block changes do not stall frames.
- Cubic chunks of 16×16×16 blocks: `ChunkData` (`scripts/voxel/chunk_data.gd`), a flat one-byte-per-block array.
- Block registry `Blocks` (`scripts/voxel/blocks.gd`) and `BlockType` (`scripts/voxel/block_type.gd`): per-face textures, optional per-face overlay, sRGB biome tint, render layer (opaque / cutout / translucent) and same-type face culling. New blocks are one `register()` call.
- 52 block types: stone, dirt, 5 biome grasses (plains, forest, taiga, swamp, savanna), cobblestone, bedrock, sand, gravel, sandstone, obsidian, water; oak/birch/spruce logs, leaves and planks; coal/iron/gold/lapis/diamond/redstone ores; iron/gold/lapis/diamond blocks; glass; 16 wool colors; crafting table and furnace (front faces +Z for now).
- Texture atlas `assets/textures/terrain.png` (16×16 tiles), sliced into a `Texture2DArray` at runtime by `BlockMaterials` (`scripts/voxel/block_materials.gd`): no tile bleeding at mip levels, nearest filtering with mipmaps and anisotropy.
- Block shaders (`shaders/`): opaque, cutout (alpha scissor: glass, leaves) and translucent (water); shared code applies tint, overlay and baked AO.
- `ChunkMesher` (`scripts/voxel/chunk_mesher.gd`): builds chunk geometry with hidden face culling, one surface per render layer; returns plain surface arrays so it can later run on worker threads.
- `VoxelWorld` (`scripts/voxel/voxel_world.gd`): owns chunks, builds their meshes and collects render stats.
- HUD shows chunk count, visible vs. naive face count, triangles, vertices and meshing time.
- `WindowControls` autoload (`scripts/window_controls.gd`): F11 / Alt+Enter toggles fullscreen and F4 VSync (both change the same settings as the Video menu), minimum window size 640×360.
- HUD shows the current window size.
- Baked per-vertex voxel ambient occlusion in `ChunkMesher`: corners and creases are darkened (0fps method: two side neighbors + diagonal), quads are split along the darker diagonal to avoid AO anisotropy.
- F3 toggles VSync; HUD shows VSync state and frame time (total and render CPU).

- `RandomBlocksGenerator` (`scripts/voxel/random_blocks_generator.gd`): debug world with a stone floor and every block type scattered randomly, to inspect texture seams, transparency, AO and shadows.
- `VoxelWorld.generator` (`TERRAIN` / `RANDOM_BLOCKS`) and `random_density`; **R** regenerates the world with a new seed.
- Retro sky shader (`shaders/sky.gdshader`): day/night color gradient, sunrise/sunset glow, textured sun and moon with halos (`assets/textures/sky/`, hidden below the horizon; the disc covers the sky and stars, the halo is added), pixel stars after dusk, flat layer of blocky drifting clouds. Details are skipped in the radiance cubemap; the sky updates incrementally at 64 px radiance.
- Moon phases like the real Moon: the terminator is computed per texture pixel (crescent, quarter, gibbous, full), waxing lit on the right and waning on the left, the dark part keeps a faint earthshine, the halo and the moonlight follow the lit fraction. A full cycle takes `lunar_cycle_days` (8 by default; 29.5 is the real value).
- Day/night cycle `DayNightCycle` (`scripts/day_night_cycle.gd`), driven by the world clock and interpolated between ticks: sun path, warm low sun, dim bluish moonlight at night, drives the sky shader. Up/Down arrows change the time of day, Left/Right rotate the sun path, time stops with `/gamerule doDaylightCycle false` (24000 ticks = 20 min per day), **M** skips to the next day. Days are counted at sunrise. HUD shows world generator, seed, day, clock time and moon phase.
- Distance fog colored by the sky (aerial perspective).
- Seasons and the analemma: the sun position is computed for an observer at `latitude_deg` with the sun's declination (axial tilt 23.44°) and the equation of time (orbit eccentricity 0.0167) over a 365.24-day year, so at the same clock time the sun traces a figure 8 over the year; summer days are longer and the noon sun higher. The game starts at the March equinox; HUD shows the calendar date. `analemma_enabled` turns it off.

### Changed
- Dropped items look and move like the modern game: items and plants are thin 3D pictures (`shaders/item_world.gdshader`) that turn around and bob like dropped blocks instead of flat pictures facing the camera; stacks show 1-5 copies (more than 1, 16, 32, 48 items); blocks drop from near the middle of the broken block and thrown items fly with the game's push. Plants (saplings, flowers, grass) are held in the hand as flat 3D pictures too.
- The hand swing while breaking is slower (8 ticks) and each swing finishes before the next starts, so holding the button no longer makes the hand twitch.
- Leaves drop like the classic game, broken or decaying: a sapling of their tree 1 time in 20, oak leaves also an apple 1 time in 200 (both can drop at once), else nothing. Drop entries can now drop besides each other (`"also"`).
- Grass under water (or under anything that lets almost no light through) turns into dirt on a random tick, and grass spreads only with enough light (9+) onto dirt that is not under water, like the modern game.
- The swing of the item in hand turns in the classic order (around Y, then Z, then X in the item's own space), so tools swing forward toward the middle of the view.
- Flowing water became flowing liquids (`LiquidBehavior`, was `WaterBehavior`) shared by water and lava.
- The window opens with the size it had last time (or maximized, if it was), always in the middle of the screen; the first start takes 3/4 of the screen (`user://window.cfg`, WindowControls). Leaving fullscreen goes back to that window.
- Flat items in hand (tools, apples) are placed exactly like the classic game's first-person item (down 0.3, x1.5, turned 50° and 335°, mirrored): tools point diagonally up toward the middle of the view.
- Title screen: a new logo built like the classic one (`tools/make_title_logo.py`): VOXEL ENGINE made of stone blocks from the block atlas, each with a darker 3D side below, a black outline and a soft shadow, and BEDROCK EDITION in smaller blocks; drawn as sharp pixel art. The logo and the buttons sit together in the middle of the screen.
- Hearts and hunger sit right above the hotbar, like the classic game.
- The loading screen island is a little lower.
- Every generated column is saved with the world (not only the changed ones), so an existing world loads from disk instead of generating its terrain again; while the loading screen is up, the columns it waits for are meshed first (nearest first, whichever way the camera looks). Loading an existing world with render distance 6: 9.3 s → 5.1 s.
- Terrain like the classic Beta generator: its noise magnitudes are restored (limit noises x128, main noise x25.5, depth x8.2), so the main noise switches sharply between the limits again: hills, cliffs, overhangs and mountains instead of mostly flat land. Biomes are about 2.5 times bigger; climate is sampled every 4 blocks and interpolated.
- Lighting like the classic game: the mesh stores the raw light level and the shaders apply the light curve; at night sky light loses up to 11 levels (the classic skylightSubtracted), so the surface darkens step by step while caves stay as they are (Classic pack; its Night Brightness option now means fewer lost levels). Ambient occlusion is applied in the shaders too: the Ambient Occlusion setting no longer re-meshes.
- The sun and moon move like the classic game: the classic celestial angle (a day of 24000 ticks, faster around noon and midnight), sunrise in the east, noon overhead, sunset in the west, the moon opposite; 8 moon phases, one per day (day 0 is a full moon). The analemma, latitude, seasons and the sun path rotation keys are removed.
- Stronger ambient occlusion: corners and wall bases are clearly darker (full strength `[0.22, 0.45, 0.68, 1.0]` by the number of blocking neighbors, was `[0.5, 0.68, 0.84, 1.0]`), with a new Ambient Occlusion setting (Quality, 0-100%). Block shadows are darker too: light levels below full fall off faster (the classic curve raised to the power 1.35), so the shade under trees, overhangs and in nooks reads clearly. The Dynamic Lighting pack's ambient light defaults to 75%.
- Faster world loading, results identical block for block: sky light builds its 48 x 48 x 128 area from 16-block row copies instead of a per-block loop and copies the output in rows (12-18 ms per column instead of 26-32 ms, single thread); the generator writes the terrain interpolation without function calls, skips ore spheres above the highest stone and starts the surface pass at the terrain top (13 ms per column instead of 20). A world at render distance 8 (361 columns) is fully loaded in 6.4 s headless, the first chunk shows after 0.6 s.
- Title screen panorama: instead of a floating island generated anew each time, always the same place of the same world (a forest of seed 1337), seen from above the treetops, the view slowly turning around on the spot like the classic panorama; a 9 x 9 column piece generated on worker threads (about 4 s), its edges hidden in fog.
- Menus opened from the title screen (world selection and creation, options) have the classic options background: dark tiled dirt, the list area darker with soft shadows under the header and above the buttons. In game the blurred world stays behind menus.
- The loading screen island shows the real loading: each of its columns is a world column around the player, as high as its terrain, and goes through every stage on screen (drops in as stone when generated, turns to dirt when lit, grows grass when meshed), one stage at a time with a small pop; the island is bigger and animates more smoothly; a tree grows when everything is ready.
- Options: Video Settings... opens the new Video Settings screen (Shaders moved there). Old toggle values of Smooth Lighting and Clouds are converted to the new choices.
- The Shadows video setting moved into the Dynamic Lighting shader pack.
- The game is called "Voxel Engine Bedrock Edition" (window title, title screen, debug screen) and the developer is MishaelS (`application/config/developer`). Settings and worlds stay in the same user folder (`config/custom_user_dir_name`).
- Title screen: the panorama is a floating island cut out of a generated world (4x4 columns, real terrain, trees and lakes, a rounded underside) that builds itself chunk by chunk, each chunk rising into place in a spiral from the middle; the panorama is slightly blurred behind the menu.
- Running the game scene directly also starts at the title screen.
- The slow natural healing is replaced by the hunger rules (healing needs food 18+).
- The intro logo now reads "https://github.com/MishaelS" in the blocky style of the original; drawn by `tools/make_intro_logo.py` (any text, same font).
- The game scene is opened from the title screen; with a saved world, R and World Settings no longer regenerate it (the generator and seed belong to the world). New survival worlds start with an empty inventory.
- Clouds scroll with real time where there is no world (title screen).
- Chunk and block meshes are stored compressed on the GPU (16-bit positions and UVs, octahedral normals): half the vertex memory and bandwidth.
- Fog no longer samples the sky per pixel (aerial perspective): its color is computed once per frame from the sky gradient. Fog, clouds and FOV are handled by Atmosphere and Player; `SettingsApplier` keeps only render distance, shadows, smooth lighting, brightness and the debug screen.
- Clouds moved out of the sky shader (it now draws only the gradient, sun, moon and stars).
- Code cleanup: world stats are built only when the debug screen asks (`VoxelWorld.get_stats()`), one worker-job limit shared by generation / light / meshing, columns are split into chunks without an extra copy (`WorldGenerator.split_column`), the spawn point is on the ground (feet) instead of eye height, starting hotbar blocks live in `Player.STARTING_BLOCKS`.
- Controls like the classic game: **Space** jumps, **Shift** sneaks, **Ctrl** sprints, **E** opens the inventory (were fly up / fly down / speed boost); key binding actions `jump`, `sneak`, `inventory`.
- Block icons are rendered by the GPU (`BlockIcons`): an orthographic view of the block's own mesh at the classic angle, at exactly the slot's pixel size, so texture pixels are sharp and even (the old CPU projection drew them unevenly). Placement is refused only where the block would overlap the player's box.
- Faster world loading (render distance 6: first chunk 2.5 s -> 0.7 s, whole area 20.9 s -> 5.3 s). In GDScript, function calls, engine method calls, Dictionary and generic Array reads serialize across worker threads, so the hot loops of generation, sky light and meshing now use only inline arithmetic on packed arrays (block / light tables, AO offsets and corner offsets as packed arrays, biomes as packed tables). Worker scaling: generation 3.6x, light 7.1x, meshing 4.6x (was below 1x).
- Columns that start no caves are skipped with an inline hash before creating a random generator; tunnels that can never reach the column are dropped early; bedrock no longer draws a random number for every block of the column. World generation for a given seed differs slightly (cave placement, bedrock pattern).
- Chunks to mesh are kept in a sorted queue rebuilt only when something changes (column lit or loaded, player moved, block changed) instead of rescanning every waiting chunk each frame: worst main-thread cost while flying dropped from ~11 ms to ~1 ms.
- Opaque and cutout block shaders use Lambert diffuse without specular (blocks are fully rough anyway).
- The crosshair copies only its own rectangle of the screen to invert the colors behind it, instead of the whole (Retina-sized) frame every frame.
- Debug screen text is rebuilt every 50 ms instead of every frame.
- Streaming pipeline: generate (render distance + 1) -> light (when the 8 neighbor columns exist; the outer ring treats unloaded neighbors as solid) -> mesh (when the 8 neighbor columns are lit). Caves are dark now instead of lit by the sky everywhere.
- `threading/worker_pool/low_priority_thread_ratio` raised to 0.75 so world jobs may use more worker threads.
- `ChunkMesher` works on a padded 18³ volume (the chunk plus a border from its 26 neighbors): faces and AO are correct across chunk borders and neighbor lookups are plain index offsets; fully buried chunks are skipped. Editing a block on a chunk border re-meshes the neighbor chunks too.
- Random ticks skip chunks without random-ticking blocks (tracked per chunk).
- Shadow presets: Low = 2 cascades up to 48 blocks, High = 4 cascades up to 64 blocks (far shadows are under fog and cost draw calls).
- The old HUD label is replaced by the debug screen (hidden by default, F3 shows it); the controls hint moved to the Controls screen.
- VSync hotkey moved from F3 to F4 (F3 is the debug screen, like the classic game).
- Mouse wheel selects the hotbar slot; fly speed is now Ctrl + mouse wheel.
- The first click only captures the mouse; clicks with the mouse captured act on blocks.
- Chat messages are shown above the hotbar.
- Main scene renders a terrain chunk instead of a single voxel; camera moved to frame the chunk.
- Blocks are textured instead of vertex-colored; voxel AO and biome tint are passed in the vertex color (rgb = tint, a = AO).
- The window starts maximized and is explicitly resizable.
- VSync is off by default, so FPS is no longer capped at the monitor refresh rate.
- Rendering optimized for high-DPI screens (measured on Apple M4, 3420×2090: 50 → ~155 FPS): SSAO removed (replaced by voxel AO), MSAA 2x replaced by FXAA, hard directional shadows.
- Main scene starts in `RANDOM_BLOCKS` mode.

### Fixed
- `assets/textures/items.png` was WebP data and could not be loaded; it is a real PNG now.
- The loading screen no longer hangs at 83% with Render Distance 2: island columns beyond the render distance (never meshed) count as done; a safety net finishes loading 6 s after the world itself is ready.
- A dark, chunk-sized rectangle on ice seen from above: translucent faces were drawn from both sides, so the backs of faces under the surface showed through. They are front-faced again; the water surface gets its own downward-facing copy, so it is still seen from under water.
- The loading screen island was cut off at the top and bottom: its view is bigger and the camera farther.
- Under water the surface was invisible from below (the sky showed through) and the sky stayed bright: water and ice faces are now drawn from both sides, so the water surface and ice are seen from below like the classic game, and the underwater fog (18 blocks) also covers the sky.
- Ice next to water showed its sides under the water's surface as pale ghost walls through the water: ice now draws only the strip of its side above the water (the water surface is 2 pixels lower), and nothing where water reaches the top. The translucent depth offset is now relative (depth is reverse Z), so it can't let faces behind show through far away.
- Ice and water drawn with dark half-squares where translucent faces overlap: translucent blocks now render in two passes (depth first, then color only for the nearest translucent surface), and water no longer draws its faces toward ice.
- The blurred background of menus and inventories showed an old frame (the title screen) instead of the world: the blur now copies the whole screen first.
- Stars were uneven blobs, too big: they are small square points like the classic game's (`shaders/stars.gdshaderinc`, shared by the game and title skies) and twinkle.
- Voxel AO was 2–3× too dark: the AO factor was applied to sRGB vertex colors and then gamma-expanded by the material (0.5 became ~0.22). Block colors are now converted to linear once and AO is applied in linear space (`vertex_color_is_srgb = false`).

### Removed
- Changing the time of day with the Up/Down arrows (and their Time Forward / Time Backward key bindings); M still skips to the next day.
- Free-flying camera (`FreeCamera`, Ctrl + mouse wheel fly speed): replaced by the player and creative flying.
- The single-chunk heightmap `TerrainGenerator` (replaced by the beta generator).
- `VoxelBlock` (`scripts/voxel_block.gd`), replaced by chunk meshing.

## [0.0.1] - 2026-11-08

### Added
- Godot 4.5 project (Forward+), 1280×720 window, MSAA 2x.
- Git settings: `.gitignore` (`.godot/` cache, builds, OS and IDE files), `.gitattributes` (LF, binary assets), `.editorconfig`.
- Main scene `scenes/main.tscn`: procedural sky, sun with shadows, SSAO, floor.
- Voxel `VoxelBlock` (`scripts/voxel_block.gd`): a 1×1×1 cube, mesh assembled manually face by face into an `ArrayMesh`.
- Free camera `FreeCamera` (`scripts/free_camera.gd`): WASD, E/Space - up, Q - down, Shift - boost, mouse wheel - speed, LMB/Esc - capture mouse.
- HUD (`scripts/hud.gd`): FPS, camera position, control hints.
- Input actions in project settings: `move_*`, `sprint`.
- README describing running, controls, and structure.

[Unreleased]: https://github.com/MishaelS/voxel-engine/compare/v0.0.30...HEAD
[0.0.30]: https://github.com/MishaelS/voxel-engine/compare/v0.0.29...v0.0.30
[0.0.29]: https://github.com/MishaelS/voxel-engine/compare/v0.0.28...v0.0.29
[0.0.28]: https://github.com/MishaelS/voxel-engine/compare/v0.0.27...v0.0.28
[0.0.27]: https://github.com/MishaelS/voxel-engine/compare/v0.0.26...v0.0.27
[0.0.26]: https://github.com/MishaelS/voxel-engine/compare/v0.0.25...v0.0.26
[0.0.25]: https://github.com/MishaelS/voxel-engine/compare/v0.0.24...v0.0.25
[0.0.24]: https://github.com/MishaelS/voxel-engine/compare/v0.0.23...v0.0.24
[0.0.23]: https://github.com/MishaelS/voxel-engine/compare/v0.0.22...v0.0.23
[0.0.22]: https://github.com/MishaelS/voxel-engine/compare/v0.0.21...v0.0.22
[0.0.21]: https://github.com/MishaelS/voxel-engine/compare/v0.0.20...v0.0.21
[0.0.20]: https://github.com/MishaelS/voxel-engine/compare/v0.0.19...v0.0.20
[0.0.19]: https://github.com/MishaelS/voxel-engine/compare/v0.0.18...v0.0.19
[0.0.18]: https://github.com/MishaelS/voxel-engine/compare/v0.0.17...v0.0.18
[0.0.17]: https://github.com/MishaelS/voxel-engine/compare/v0.0.16...v0.0.17
[0.0.16]: https://github.com/MishaelS/voxel-engine/compare/v0.0.15...v0.0.16
[0.0.15]: https://github.com/MishaelS/voxel-engine/compare/v0.0.14...v0.0.15
[0.0.14]: https://github.com/MishaelS/voxel-engine/compare/v0.0.13...v0.0.14
[0.0.13]: https://github.com/MishaelS/voxel-engine/compare/v0.0.12...v0.0.13
[0.0.12]: https://github.com/MishaelS/voxel-engine/compare/v0.0.11...v0.0.12
[0.0.11]: https://github.com/MishaelS/voxel-engine/compare/v0.0.10...v0.0.11
[0.0.10]: https://github.com/MishaelS/voxel-engine/compare/v0.0.9...v0.0.10
[0.0.9]: https://github.com/MishaelS/voxel-engine/compare/v0.0.8...v0.0.9
[0.0.8]: https://github.com/MishaelS/voxel-engine/compare/v0.0.7...v0.0.8
[0.0.7]: https://github.com/MishaelS/voxel-engine/compare/v0.0.6...v0.0.7
[0.0.6]: https://github.com/MishaelS/voxel-engine/compare/v0.0.5...v0.0.6
[0.0.5]: https://github.com/MishaelS/voxel-engine/compare/v0.0.4...v0.0.5
[0.0.4]: https://github.com/MishaelS/voxel-engine/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/MishaelS/voxel-engine/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/MishaelS/voxel-engine/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/MishaelS/voxel-engine/releases/tag/v0.0.1
