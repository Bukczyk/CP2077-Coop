# Shared goals and work split

**Proposal for Bukczyk to review.** KyleBuildsAI approved publishing this goal list. The first NPC goal comes from Bukczyk's proposal. The later goals and their order need agreement; this document does not assign active tasks or claim completed features.

KyleBuildsAI and Bukczyk are working toward one Cyberpunk multiplayer mod in **Bukczyk/CP2077-Coop**. Start here for the plain-English work split. Read the [collaboration guide](COLLABORATION.md) for the detailed AI work rules.

## The basic agreement

For every shared goal, agree on four things:

1. **The result:** What should players see or be able to do?
2. **The split:** What does KyleBuildsAI build, and what does Bukczyk build?
3. **The connection:** What information do the two parts exchange?
4. **The test:** How do we prove that the complete feature works?

This agreement lets both people work toward the same result at different times.

## Who does what?

**KyleBuildsAI handles the game side.** Read information from Cyberpunk and make received information appear correctly inside Cyberpunk. This includes NPC models, player appearance, movement, animations, map icons, cars, seats and live-game tests. It includes engine behavior as well as visuals.

**Bukczyk handles networking and shared-state rules.** Manage sessions, identify players and objects, check who may change them, send their information, deliver the host's accepted results and restore state after a connection problem. This includes network update rates, message ordering and delivery reliability.

**Both handle the connection between their work.** Agree on the information and calls before building connected changes. Neither side changes that agreement alone.

The host is the player whose game decides the supported world outcomes. Either maintainer can play as host or joiner. These player roles are separate from development responsibilities.

## Goal 1: Both players see the same NPC

**Result:** A selected NPC has the same identity, supported appearance and position in both games.

**KyleBuildsAI:** Read the NPC's model and appearance in the host's game. Create or update the matching NPC in the joining player's game. Make it visible and movable. Prevent that copy from independently choosing to run, attack or fight.

**Bukczyk:** Give that NPC a shared identity. Carry the agreed appearance and position information between the computers. Tell the joining game when that NPC should be created, updated or removed.

**Test together:** Start with one controlled NPC. If the host has a male NPC in a red jacket, the joiner should see the agreed matching model and clothing. Move the host's NPC and verify that the same joining NPC follows. Confirm that the joining copy does not make independent AI decisions. Agree which appearance details this first test supports before coding.

**First task on KyleBuildsAI's side:** Verify or fix the visible, movable NPC copy without independent AI. Inspect the existing implementation first. A proposed engine class is something to investigate, not a guaranteed solution.

## Goal 2: Both players see the same NPC reaction and damage

**Result:** A joining player interacts with or hits the NPC. The host decides the reaction and damage. Both players see the accepted result.

**KyleBuildsAI:** Detect the supported interaction or hit in the game. Connect it to the host's engine behavior and read the actual result. Make the joining game display the accepted reaction, health change or death.

**Bukczyk:** Deliver the request to the host and send the accepted result back to the players. Reject invalid requests and prevent repeated messages from applying the same event twice.

**Test together:** Try one interaction, one nonlethal hit and one lethal hit. Both games must agree on the result. Reconnect and confirm that a dead NPC does not incorrectly return alive.

Goals 1 and 2 form Bukczyk's stated immediate milestone. Check that the matched host/joiner session works before running these tests. Later goals below need an agreed order and specific assignments.

## Goal 3: Players look and move correctly

**Result:** Players see the correct supported appearance, direction, movement and actions, including aiming down sights.

**KyleBuildsAI:** Read appearance and actions from the game. Apply received information to the other player's representation. Make movement and animations look correct and smooth.

**Bukczyk:** Deliver the agreed player information at suitable rates and reject outdated updates.

**Test together:** Walk, sprint, crouch, jump, turn and aim. Compare both views and measure visible delay. Network delay and game-side animation delay are different measurements; investigate the actual cause together.

## Goal 4: Find teammates on the map

**Result:** The map and minimap show teammates at the correct locations, with an arrow for facing direction.

**KyleBuildsAI:** Adapt the existing minimap work. Create, move and remove the icons. Add the agreed direction indicator.

**Bukczyk:** Supply the correct player identity, position, direction and departure information through the shared session system.

**Test together:** Move apart, turn, disconnect and reconnect. Verify that markers follow the right players and old markers disappear.

Record the source of the existing marker, its integration task and its verified result. Reviewing the earlier code does not mean it has been added to the shared project.

## Goal 5: Ride in the same vehicle

**Result:** Both players see the matching vehicle. One can drive while another sits in a real passenger seat.

**KyleBuildsAI:** Read and reproduce the supported vehicle model and appearance. Make entry, seats, driving presentation, exit and cameras work inside the game. Confirm actual seat entry before reporting success.

**Bukczyk:** Manage the vehicle's shared identity, accepted driver and seat reservations. Carry vehicle state and seat changes between computers.

**Test together:** Enter one supported car, drive, stop and exit. Check both views and actual seats. Then test interrupted connections and conflicting seat requests.

## Goal 6: Recover from connection problems

**Result:** Players can reconnect without duplicate players, NPCs or vehicles and without losing the correct supported session state.

**KyleBuildsAI:** Detect and clean up old game representations. Rebuild the correct visible state when fresh session information arrives. Show useful connection messages.

**Bukczyk:** Detect connection loss, restore current session information and reject messages from an old connection or world state.

**Test together:** Interrupt a connection and reconnect. Repeat under delayed or lost network messages. Check the actual game result, not just successful message delivery. Basic reconnect tests should also accompany each earlier goal.

## Goal 7: Make the combined build easy to test and install

**KyleBuildsAI:** Prepare the matching Windows game files, clear installation steps, rollback and useful game logs.

**Bukczyk:** Prepare the matching server files, configuration and server logs.

**Both:** Identify the exact source and versions used. Run the same scenario on two separate computers. Publish a complete tested package through an agreed release task, retaining previous releases.

For each requested new runtime/package version, refresh KyleBuildsAI's complete local package and record the matching release and hashes under [KyleBuildsAI's existing release checklist](https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/docs/RELEASE_WORKFLOW.md). Documentation changes alone do not need a new game package.

## How work continues while the other person sleeps

- Write the goal, owner, affected files, required information and test before starting.
- Test each part separately while it is being built. KyleBuildsAI can test game behavior using sample messages; Bukczyk can test message delivery and session rules.
- Sample-message tests are development checks. The final proof is the combined feature working between real game clients.
- Connect small completed pieces early. Do not wait until every feature is finished.
- Ownership remains with the assigned person until an explicit handoff.
- If a dependency is missing, leave a clear request and continue independent assigned work.
- Before stopping, leave the latest commit, results, failures and next step with a UTC timestamp, a common time reference for both people.

## Where information belongs

**Private messages:** Discuss ideas, ask questions and agree on priorities in short, plain sentences.

**GitHub:** Keep the shared tasks, ownership, agreed information formats, code changes, reviews and test results. A PR is a page showing proposed code or documentation changes before they enter the shared version.

**Obsidian:** Keep KyleBuildsAI's research, explanations, test notes and links to the shared records. Bukczyk's AI cannot be expected to know an agreement that exists only in this local vault.

After reaching an agreement in private messages, arrange for one person to put the decision in the shared GitHub task. Say who will record it. Each AI reads that shared record before implementation. This note itself does not authorize an AI to send private messages or publish new decisions.

## The race example

A multiplayer race was an example used to understand the work split. It is not an agreed next feature.

If both maintainers choose it later, KyleBuildsAI would implement the in-game route, checkpoints, countdown, race rules and results screen. Bukczyk would implement the agreed race/session messages and delivery. Both would agree on the official result authority and finish-time rules. Each side could test its part separately, then test the complete race together.
