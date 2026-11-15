extends RefCounted
## Outer layout/hit rectangle only; native glyph rendering remains independent.
## UIRoot's last active child: zero group padding/spacing, no force expansion.
const SOURCE_COMMIT = "a11a89b04cea8370476f2559b639bb9b4cbc08d8"
const HEIGHT = 73.5199966430664
const WIDTHS = {"Feed People": 210.58999633789062, "Start Day": 164.5399932861328, "Return to Title": 227.07000732421875}
static func resolve(data: Dictionary, label: String) -> Vector2:
	var provenance = data.get("provenance", {})
	if not provenance is Dictionary or provenance.get("source_commit", "") != SOURCE_COMMIT or not WIDTHS.has(label): return Vector2.ZERO
	# Locked English callsites; primary static font, size30, margins20 per side.
	# Preferred values follow TMP scalar rounding. Not translated-label metrics.
	return Vector2(WIDTHS[label], HEIGHT)
