extends RefCounted
## Explicit button transactions remain native; source overlays have no raw Cancel.
const SOURCE_COMMIT := "a11a89b04cea8370476f2559b639bb9b4cbc08d8"
static func admits(data: Dictionary, destination: String) -> bool:
 if data.get("provenance", {}).get("source_commit", "") != SOURCE_COMMIT: return false
 var expected: Dictionary = {
  "preferences": {"id":"519257449", "class":"GameplayPrefsUI", "script":"1353d149f9e31c44ab88d96e0f04e8d8", "link":"gameplayPrefsUI", "button":"newGameButton", "opener":"2057193291", "close":"cancelButton", "close_id":"964648665"},
  "saves": {"id":"2090943499", "class":"SavedGamesUI", "script":"a00b831b243a80d44ba40405f3d262e3", "link":"savedGamesUI", "button":"loadGameButton", "opener":"2053956281", "close":"closeButton", "close_id":"1958241573"}
 }.get(destination,{})
 if expected.is_empty(): return false
 var title: Dictionary = {}; var overlay: Dictionary = {}
 for scene in data.get("scenes", []):
  if scene.get("name", "") != "Title": continue
  for doc in scene.get("documents", []):
   if doc.get("script_class", "") == "PauseMenu": return false
   if str(doc.get("file_id", "")) == "1960366055" and doc.get("script_class", "") == "TitleScreen": title = doc.get("fields", {})
   if str(doc.get("file_id", "")) == expected.id and doc.get("script_class", "") == expected["class"]: overlay = doc.get("fields", {})
 if title.get("m_Enabled",0) != 1 or title.get("m_Script",{}).get("guid","") != "7ceb2876a137ca34e88ae1d005e367d8": return false
 if str(title.get(expected.link,{}).get("fileID","")) != expected.id or str(title.get(expected.button,{}).get("fileID","")) != expected.opener: return false
 if overlay.get("m_Enabled",0) != 1 or overlay.get("m_Script",{}).get("guid","") != expected.script or str(overlay.get(expected.close,{}).get("fileID","")) != expected.close_id: return false
 return destination != "preferences" or str(overlay.get("confirmButton",{}).get("fileID","")) == "1858458969"
