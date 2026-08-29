Dialogue UI 1.0.5 d - Wrath 3.3.5a backport r3

Target
  WoW 3.3.5a, build 12340, Interface 30300.
  The compatibility layer avoids relying on Ascension-only APIs, so the same
  package can be used on other 3.3.5a-based clients.

Install
  Keep the folder and TOC name exactly "DialogueUI-Ascension".
  Place the folder under Interface\AddOns, then fully restart the client.

Legacy safety
  Wrath treats UIParent visibility, dynamically reparented secure action
  overlays, and raw keyboard capture differently from Retail. This build keeps
  UIParent visible and disables camera/UI hiding, addon-provided one-click item
  actions, and Dialogue UI keyboard/gamepad navigation on legacy clients. Use
  the visible mouse controls and normal bag/action-bar buttons. These safeguards
  keep the addon out of protected action state and prevent it from swallowing
  ability keys used by action bars such as ElvUI.

Optional APIs
  Ascension's native gossip-ID and text-to-speech extensions are used when they
  are actually present. Other 3.3.5a servers use title/index quest fallbacks and
  hide unsupported TTS controls instead of advertising nonfunctional features.
  Ordinary armor and weapon previews use Wrath's DressUpModel; Retail-only pet,
  mount, transmog-source, housing, and ModelScene previews are unavailable.

Conflicts
  The Ascension integration suspends competing quest/gossip event ownership
  from Immersion and DialogKey while Dialogue UI owns the interaction, then
  restores it afterward.
