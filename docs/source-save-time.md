# Persisted save time

Source lock: CardLoop a11a89b04cea8370476f2559b639bb9b4cbc08d8.

- `Assets/StackCraft/Scripts/SaveSystem/GameData.cs:16`: LastSaved is System.DateTime.
- `Scripts/Core/GameDirector.cs:107-114`: after OnBeforeSave, assign DateTime.Now, then serialize. The timestamp belongs to the saved state, not filesystem metadata.
- `Scripts/SaveSystem/SaveSystem.cs:15-25`: JsonConvert.SerializeObject(data, Formatting.Indented), no local serializer date-format customization at this call.
- `Scripts/UI/Title/SavedGameSlot.cs:30`: interpolates DateTime directly, with no explicit format/culture. Source display therefore depends on .NET culture.

Native version-1 campaign gains optional `last_saved` object with local ISO wall clock and UTC offset minutes. Capture and load preserve it; only save_file stamps a newly captured snapshot. Successful commit updates live metadata, failed writes do not. Existing backup/temporary/atomic-rename sequence is unchanged. Inventory gets the timestamp from the chosen validated primary or backup. Existing slot view already accepts persisted timestamp provenance. Missing legacy fields remain unknown; independently labeled file mtime is not promoted into saved time. No existing save is rewritten merely by loading/listing it. Archive restore creates a new save and thus records the new save operation; original archive remains untouched.

Scope limitations: native format is not Unity JSON compatibility. Time is sampled at whole-second resolution; original DateTime may contain finer precision. Native display explicitly uses ISO local date/time with offset, not a guessed .NET current-culture format. Godot obtains local clock and timezone in separate system calls; a timezone/DST transition between those calls is not an atomic DateTime.Now equivalent. No claim of exact culture/precision equivalence. These remaining differences are explicit rather than hidden behind mtime.

Public test `test_save_timestamp.gd` uses synthetic campaigns and an isolated user-data test directory only. Tests missing legacy values, restore/capture, invalid metadata/date rejection, successful commit, failed commit, backup preservation/recovery, and slot display provenance. Existing saves are never accessed.
