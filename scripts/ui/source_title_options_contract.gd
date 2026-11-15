extends RefCounted
## Locked TitleScreen.Start opens this Options instance; neither owns raw Cancel.
const SOURCE_COMMIT := "a11a89b04cea8370476f2559b639bb9b4cbc08d8"
static func admits(data: Dictionary) -> bool:
 if data.get("provenance", {}).get("source_commit", "") != SOURCE_COMMIT: return false
 var title: Dictionary = {}
 var linked: Dictionary = {}
 var options: Dictionary = {}
 for scene in data.get("scenes", []):
  if scene.get("name", "") != "Title": continue
  for doc in scene.get("documents", []):
   if doc.get("script_class", "") == "PauseMenu": return false
   if str(doc.get("file_id", "")) == "1960366055" and doc.get("script_class", "") == "TitleScreen": title = doc.get("fields", {})
   if str(doc.get("file_id", "")) == "436739394" and doc.get("script_class", "") == "GameOptionsUI": linked = doc.get("fields", {})
 for prefab in data.get("referenced_prefabs", []):
  if prefab.get("guid", "") != "386f59785c880f546bf078b8023091a8": continue
  for doc in prefab.get("documents", []):
   if str(doc.get("file_id", "")) == "98810512149128886" and doc.get("script_class", "") == "GameOptionsUI": options = doc.get("fields", {})
 return title.get("m_Enabled", 0) == 1 and title.get("m_Script", {}).get("guid", "") == "7ceb2876a137ca34e88ae1d005e367d8" and str(title.get("gameOptionsButton", {}).get("fileID", "")) == "1573722792" and str(title.get("gameOptionsUI", {}).get("fileID", "")) == "436739394" and linked.get("m_Enabled", 0) == 1 and linked.get("m_CorrespondingSourceObject", {}).get("guid", "") == "386f59785c880f546bf078b8023091a8" and str(linked.get("m_CorrespondingSourceObject", {}).get("fileID", "")) == "98810512149128886" and options.get("m_Enabled", 0) == 1 and options.get("m_Script", {}).get("guid", "") == "14a040b8aaafd8342878bfa503b99721" and str(options.get("closeButton", {}).get("fileID", "")) == "3374842419896805458"
