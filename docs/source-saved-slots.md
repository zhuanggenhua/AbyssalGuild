# Source SavedGames rows and safe native transactions

`source_saved_slot.gd` resolves SavedGameSlot's labelText/loadButton/deleteButton
references, not arbitrary GameObject names. Source Content padding10/spacing10,
fixed height100, and the 20-wide permanent scrollbar allocation yield 760-wide
rows in the source 800-wide panel. Label requests600×80 at(10,10); action rows
request130×40 at(620,10) and(620,50). Source Image/font/color and vertical text
alignment are mapped. Exact TTF binding uses SourceFontRegistry when available.
The source action labels use TMP Flush alignment16; full TMP justification and
wrapping metrics remain explicitly unverified, recorded on the controls. No
font-size reduction conceals that remaining difference.

## Connected behavior

SavedGames now shows rows, not duplicate native selector UI. The existing hidden
OptionButton remains the transaction selection model. `saved_slot_callback_bridge`
resolves the current item ID, emits its existing item_selected signal once and
then requests the existing load/archive action. Stale rows and invalid loads are
rejected; modal/recovery/transition guards are retained. TextButton helper supplies
hover underline, action-before-sound, disabled and hidden-event protection.

The source Delete action is deliberately labelled **Archive**, never presented as
permanent deletion. Preparing, confirming, stale-plan validation, cancel, failure
rollback and restoring a copy remain existing native transactions. Native recovery
and legacy-adoption controls live in a separate clearly labelled Recovery tools
window. Escape closes that window without closing SavedGames; focus returns to its
opener. Source footer widths are remeasured with the bound font, but native font
measurement is not mislabelled as exact TMP preferredWidth. Overflow refusal leaves
the existing source rectangles rather than inventing a text-shrinking rule.

## LastSaved is not filesystem mtime

Source GameDirector.SaveGame invokes OnBeforeSave, sets GameData.LastSaved from
DateTime.Now and persists it. Native Campaign.capture has no such field. Existing
native saves therefore cannot recover an equivalent LastSaved from modified_unix.
Rows explicitly say **File modified: … UTC**, including backup provenance, or
Last Saved: unavailable when no timestamp is known. A genuine future persisted
save-field timestamp requires explicit provenance. This batch makes no save-schema
change and does not silently re-date old saves.

## Scroll boundary and corrected source-version evidence

The full locked source repository has Unity6000.5.4f1 and com.unity.ugui2.5.0.
Earlier reports that these files were missing were sparse-checkout mistakes.
Current official uGUI ScrollRect main was inspected: elastic drag/release,
unscaled inertia, bounds adjustment, wheel events and normalized scrollbar updates
are distinct algorithms. Initial official 2.5.0 raw-tag probes returned404;
main has not been proven identical to that package. This batch therefore retains
a clearly identified **native scrolling fallback**, not a claim that Godot's
ScrollContainer equals Unity's elastic ScrollRect. Row geometry and permanent
20-wide scrollbar allocation are source-backed; elastic motion and scrollbar
skin remain unfinished.

Reference inspected (not copied into this repository):
https://github.com/Unity-Technologies/uGUI/blob/main/com.unity.ugui/Runtime/UGUI/UI/Core/ScrollRect.cs

## Evidence

Synthetic tests cover geometry requests, immutable inventory, callback bridge,
stale-ID rejection, timestamp provenance and fitting footer calculations. Private
board tests cover actual760×100 rows, hidden selector, source TextButton behavior,
modal blocking, archive cancel/confirm, restore, load and recovery focus. Existing
slot UI50, management UI24, Title navigation24 and menu-focus64 regressions passed.
No private source JSON or original media was added. Native screenshot acceptance
is separate and still required.


## Exact uGUI source provenance follow-up

The version source has now been located, rather than being unavailable: official
Unity-Technologies/uGUI commit `b394b8ab4f985d25230da1bb02268dcb3c85cb19` mirrors
Unity 6000.5.4f1, matching this locked project's editor. Package 2.5.0 is built-in,
which explains why registry/tag probes were insufficient. This resolves source
availability, not the pending implementation/verification of ScrollRect elasticity,
inertia and scrollbar behavior. The current native-scroll boundary still applies.


## Follow-up integration

SavedGames now uses a version-pinned vertical Elastic ScrollRect motion adapter
instead of native ScrollContainer motion. Source wheel, drag threshold, inertia,
bounds and normalized position are covered separately from the still-native
scrollbar appearance/input; see [ScrollRect](source-scrollrect.md). New native
saves persist the save operation's local wall-clock timestamp, while legacy
saves with no field remain unknown and may show clearly labeled file mtime; see
[save time](source-save-time.md). Earlier unavailable/not-yet-implemented notes
above describe the initial audit, not these follow-up implementations.
