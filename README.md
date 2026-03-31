# PM Alert

Whisper alerts for **World of Warcraft**: plays the default tell sound and shows a **soft, colored gradient** along the screen edges when you receive a **whisper** or **Battle.net whisper**.

The edge pulse is meant to be noticeable without a hard cut-off—it fades smoothly using your chosen color.

---

## Slash commands

All commands use the **`/pmalert`** prefix.

| Command | Description |
|--------|-------------|
| `/pmalert` | Same as `/pmalert help` — lists commands in chat. |
| `/pmalert help` | Shows command list and a short note about the whisper pulse. |
| `/pmalert options` | Opens the addon panel (retail: **Escape → Options → AddOns → PM Alert**). Alias: `/pmalert config`. |
| `/pmalert test` | Plays the tell sound and runs the **same repeating pulse** as a real whisper (stops when you **click the chat window or tab** or `/pmalert dismiss`, or after 10 minutes). |
| `/pmalert dismiss` | Stops the **repeating whisper pulse** if it is active. Alias: `/pmalert stop`. |
| `/pmalert pink` | Resets the flash color to the default pink and updates the options color swatch when possible. |

---

## Options (in-game)

Open **Escape → Options → AddOns → PM Alert** (or `/pmalert options` on supported clients).

| Setting | What it does |
|--------|----------------|
| **Flash color** | Blizzard color picker (including hex). Controls the edge gradient tint. |
| **Fade-out duration** | Influences how **fast** the edge **pulse** breathes (test + whispers; longer = slower). |
| **Flash intensity** | Peak opacity of the edge flash. |
| **Edge thickness** | Size in pixels of the gradient band (larger = wider, softer glow toward the center). |

Settings are saved in **`PMAlertDB`** (account-wide saved variables).

---

## Whisper pulse (until you “acknowledge” chat)

WoW does **not** expose a true “message read” API. PM Alert stops the repeating edge pulse when you **click** the default chat UI:

- The **chat message area** (`ChatFrame` / floating frame)
- A **chat tab** (including via Blizzard’s `FCF_Tab_OnClick` hook)

Scrolling or opening the edit box alone **does not** stop the pulse.

The pulse also **stops automatically after 10 minutes** so it cannot run forever.

If you use an addon such as **WIM** that does not use the default chat frames, those hooks may never run—use **`/pmalert dismiss`** to stop the pulse manually.

**Battle.net whispers** (`CHAT_MSG_BN_WHISPER`) are treated the same as normal whispers for sound and pulse.

---

## Files

| File | Role |
|------|------|
| `TestAddon.toc` | Addon manifest and load order. |
| `Core.lua` | Events, overlay, slash commands, whisper logic. |
| `Options.lua` | Retail **Settings** panel (sliders + color swatch). |
| `README.md` | This documentation. |

---

## Author

Merto
