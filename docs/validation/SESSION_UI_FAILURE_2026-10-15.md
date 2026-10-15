# Session UI lookup failure and cleanup

KyleBuildsAI, 2026-10-15 UTC. PR15 follow-up to `a4766d6`.

After the main update failed, the session UI called `Game.GetPlayer()` outside
the protected update. A persistent engine lookup exception therefore escaped
every later failed-mode tick before marker and actor cleanup could progress.

The failed UI sample now protects this lookup. Unknown player presence disables
the reconnect button while retaining the existing stopped-bridge message.
Cleanup continues through the existing owner paths without inventing a player
handle or declaring an uncertain marker removed.

The real CET entrypoint regression seeds an exact owned marker, makes the first
cleanup attempt unavailable, then keeps player lookup throwing while cleanup
becomes available. The old code throws out of the failed-mode tick; the fix
allows the owned marker to retire. No render, networking or protocol change.

Focused lifecycle regression passes Lua 5.4 and LuaJIT. This is offline evidence;
no game launch, installed file change or live cleanup result is claimed.
