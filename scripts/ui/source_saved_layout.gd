extends RefCounted
## Deterministic source layout with explicit text measurement input.
static func rows(viewport_width: float, heights: Array, padding: Vector4, spacing: float) -> Dictionary:
	var y := padding.y
	var rectangles: Array[Rect2] = []
	for height in heights:
		rectangles.append(Rect2(padding.x,y,maxf(0,viewport_width-padding.x-padding.z),float(height)))
		y += float(height)+spacing
	return {"rectangles":rectangles,"preferred_height":y+padding.w-(spacing if not heights.is_empty() else 0.0)}
static func footer(size: Vector2, preferred_widths: Array, fixed_heights: Array, padding: Vector4, spacing: float) -> Dictionary:
	if preferred_widths.size() != fixed_heights.size(): return {"ok":false,"reason":"Mismatched child measurement counts"}
	var total := padding.x+padding.z+spacing*maxi(0,preferred_widths.size()-1)
	for width in preferred_widths: total += float(width)
	if total > size.x:
		return {"ok":false,"reason":"Preferred text does not fit; source min-width/wrapping metrics required"}
	var x := padding.x+(size.x-total)/2
	var rectangles: Array[Rect2] = []
	for index in preferred_widths.size():
		var height := float(fixed_heights[index])
		rectangles.append(Rect2(x,padding.y+(size.y-padding.y-padding.w-height)/2,float(preferred_widths[index]),height))
		x += float(preferred_widths[index])+spacing
	return {"ok":true,"rectangles":rectangles}
