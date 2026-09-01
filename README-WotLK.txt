Dialogue UI 1.0.5 d - Wrath 3.3.5a backport r28

Target
  WoW 3.3.5a, build 12340, Interface 30300.
  The compatibility layer avoids relying on Ascension-only APIs, so the same
  package can be used on other 3.3.5a-based clients.

Install
  Keep the folder and TOC name exactly "DialogueUI-Ascension".
  Place the folder under Interface\AddOns. Updating Lua/XML files only requires
  /reload; restart the client only when installing new image assets while WoW
  is already running.

Legacy safety
  Wrath treats UIParent visibility, dynamically reparented secure action
  overlays, and raw keyboard capture differently from Retail. This build keeps
  UIParent visible and disables camera/UI hiding, addon-provided one-click item
  actions, and unsafe raw keyboard/gamepad capture on legacy clients. The
  configured Confirm key is instead scoped to a visible, enabled Accept,
  Continue, or Complete Quest button and is released on page changes, hiding,
  combat, and world transitions. Visible gossip and quest-list choices 1-9 use
  temporary numbered bindings with the original themed keycap treatment; the
  full numbered set is consumed immediately after a choice to prevent repeats
  while the server changes pages. Escape closes the active Dialogue UI panel.
  These safeguards keep the addon out of protected action state and prevent it
  from swallowing ability keys used by action bars such as ElvUI.

Controls and layout
  Press F1 while a Dialogue UI interaction is visible to open settings. Ctrl +
  mouse wheel scales the hovered quest or settings panel and selects Custom
  sizing. Drag a panel from its non-interactive header/background while frames
  are unlocked; holding Shift temporarily permits dragging a locked panel.
  Scale and position are saved independently for the quest and settings panels.
  The UI page offers X-Large and Custom frame sizes plus a 10-24 pt Custom font
  size. Reset Frame Positions restores automatic placement.

Optional APIs
  Ascension's native gossip-ID and text-to-speech extensions are used when they
  are actually present. Other 3.3.5a servers use title/index quest fallbacks and
  hide unsupported TTS controls instead of advertising nonfunctional features.
  Ordinary armor and weapon previews use Wrath's DressUpModel; Retail-only pet,
  mount, transmog-source, housing, and ModelScene previews are unavailable.

Conflicts
  The Ascension integration suspends competing quest/gossip event ownership
  from Immersion and DialogKey while Dialogue UI owns the interaction, then
  restores it afterward. Ascension's custom gossip manager remains available
  for item-driven panels such as the Travel Permit, while its stock Blizzard
  GossipFrame fallback is gated to prevent a duplicate panel beside Dialogue UI.

Diagnostics
  Dialogue UI records up to 12 of its own Lua errors in the account-wide
  DialogueUI_Diagnostics SavedVariable without suppressing the normal error
  handler. Run /duierrors to open a selected, copy-ready report, then paste it
  into support. Run /duierrors clear to reset only this diagnostic history.
