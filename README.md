# Multiplayer Time Controls (Project Zomboid, build 42)

The single-player speed buttons, in multiplayer: **pause**, **normal speed** and the three
**fast-forward** speeds (5, 20 and 40 times), in the same place under the clock, and on the same
keys you already use in single player.

The speed is **one speed for the whole server**. When somebody pauses or fast-forwards, it happens
for everyone, and everyone sees who did it.

- **Buttons** at the top right, where single player has them. The speed that is on is red. A line
  under them says who changed the speed, or why it went back to normal.
- **Your own speed keys** work (Options, Key Bindings: Pause, Normal Speed, Fast Forward x1, x2,
  x3; F2 to F6 unless you changed them).
- **Pause** stops the world for everybody: the clock, zombies, hunger, actions, and every player's
  character. The screen says "Game paused by ...". Chat, the inventory and the menus keep working.
  Press pause again to go back to the speed it was at, or pick a speed.
- **Fast forward ends by itself when somebody needs normal speed**, for everyone at once:
  - a player presses a movement key, attacks, drives, or drags a body (as in single player)
  - zombies are after a player or close to one
  - a player dies
- **The server owner decides** who may change the speed, whether pausing is allowed, and how fast
  it may go.

## What the server owner decides

Three sandbox options, on the page **Multiplayer Time Controls** (in the server's settings):

| Option | Default | What it does |
|---|---|---|
| Who can change the speed | Everyone | Admins only: other players still see the buttons and the current speed, but cannot press them. |
| Pausing allowed | on | Off: the pause button does nothing. |
| Fastest speed | Fast forward x3 (40 times) | The fastest button that works: none, x1 (5 times), x2 (20 times) or x3 (40 times). |

The server checks these, not the player's game. Two things are always allowed, whatever the first
option says: fast forward ending by itself (above), so nobody is stuck at 20 times speed with a
zombie walking up; and a pause or fast forward never outlives the people who could end it (it goes
back to normal when the server is empty, or when the last admin leaves an "Admins only" server).

## What it needs

- Project Zomboid **build 42.22 or newer** (made and tried on 42.22.2).
- **The server and every player need the mod.** It does nothing in single player, which has its own
  buttons.

## Install from the Steam Workshop

Subscribe to [Multiplayer Time Controls on the Workshop](WORKSHOP_URL).

For a server, add both of these to its settings (Host, your server's settings; or the `.ini`):

```
WorkshopItems=WORKSHOP_ID
Mods=MultiplayerTimeControls
```

Players who join then get the mod from Steam by themselves. The Workshop copy and the GitHub release
are the same files.

## Install with Mod Loader

1. In [Mod Loader](https://github.com/MichaelRyan2319/ModLoader), add the game **Project Zomboid**.
   Mod Loader suggests the right mods folder by itself: `C:\Users\<you>\Zomboid\mods`.
2. Add the mod `MichaelRyan2319/ProjectZomboid-MultiplayerTimeControls`. Mod Loader installs it and
   keeps it up to date.
3. Add **Multiplayer Time Controls** to the server's mods (Host, your server's settings, Mods; or
   `MultiplayerTimeControls` in the `Mods=` line of the server's `.ini`) and have each player
   install it the same way. If you have both this copy and the Workshop one, the game uses the
   Workshop one.

## Install by hand

Download `MultiplayerTimeControls.zip` from the
[latest release](https://github.com/MichaelRyan2319/ProjectZomboid-MultiplayerTimeControls/releases/latest)
and unzip it into `C:\Users\<you>\Zomboid\mods` (in Explorer: `%UserProfile%\Zomboid\mods`), so that
you get `Zomboid\mods\MultiplayerTimeControls\42\mod.info`. Then add it to the server's mods as in
step 3 above.

## Good to know

- **Everybody moves faster in fast forward**, as in single player: a character on a walk-to or busy
  with an action goes 5, 20 or 40 times as fast. Pressing a movement key yourself ends it.
- **The speed anti-cheat is off while the world runs fast.** A dedicated server normally kicks a
  player who covers more than 20 tiles in a real second, and a character walking at 20 times speed
  does. So while fast forward is on, the mod switches that one check (the server option
  `AntiCheatSpeed`) off, and puts the server's own setting back five seconds after the speed is
  normal again. This is done in the server's memory; the server's `.ini` is not changed. If you
  would rather keep the check on at all times, set **Fastest speed** to "No fast forward".
- **During a pause the game draws its interface directly.** With the game's option "Render UI
  offscreen" on (the default), windows and chat are only redrawn as game time passes, so they would
  freeze in a pause. The mod holds that option off for the length of a pause and puts it back
  afterwards. A small file, `Zomboid\Lua\MultiplayerTimeControls.ini`, notes this meanwhile, so a
  game that was closed in the middle of a pause is put right the next time the mod loads.
- **Sleeping** is unchanged. A server that lets players sleep still fast-forwards when everyone is
  asleep, by the game's own rules.
- **A dead player** on the death screen is left alone by the mod; the rest of the server carries on
  at whatever speed it is at.

## Uninstall

Take the mod out of the server's mods, then remove it in Mod Loader, unsubscribe on the Workshop, or
delete `Zomboid\mods\MultiplayerTimeControls`. Nothing is stored in the world. The file
`Zomboid\Lua\MultiplayerTimeControls.ini` can be deleted.

## What has been tried

On build 42.22.2, against a dedicated server with one player (a normal account, and the admin
account): game time at 5, 20 and 40 times on the server and in the player's game together; pause,
with the interface still drawing; picking up and dropping an item at every speed; walking at 5 and
20 times speed without being kicked (and being kicked within a second before the mod handled the
anti-cheat); zombies appearing 8 tiles away at 20 times speed, with the world back at normal speed
within a second; a death ending fast forward; the buttons by mouse clicks; the three server options;
an "Admins only" fast forward ending when no admin is online; leaving while paused and while fast,
and joining again.

Tried only in part: the five keys were run through the mod's key handler with each key's code,
without a real key press; and "a movement key, an attack or driving ends fast forward" was tried by
making the call the game makes in those cases, not by pressing the keys.

Not tried yet: **two or more players at once**, a server hosted from the game's Host screen, a
controller, and vehicles (driving in fast forward, or being in a car when somebody pauses).

## Development

The release file is built with
`git -c core.autocrlf=false archive --format=zip -o dist/MultiplayerTimeControls.zip HEAD MultiplayerTimeControls`.
The Workshop page's text, tags and picture are in `workshop/`; the same commit's
`MultiplayerTimeControls` folder is what gets uploaded there.
