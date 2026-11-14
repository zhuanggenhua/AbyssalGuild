extends Control
## Bounded source Stats box; native glyph rendering is not TMP SDF.
const Fonts=preload("res://scripts/ui/source_font_registry.gd")
const Measure=preload("res://scripts/ui/tmp_single_line_layout.gd")
signal layout_contract_changed
var native_label:Label
var source_record:Dictionary={}
var binding:Dictionary={}
var source_height:=0.0
var group_source_enabled=true
var source_min=Vector2.ZERO
var expected_min:=Vector2.ZERO
var contract:Dictionary={"ok":false,"reason":"unconfigured"}
var text:String="":
 set(value):
  text=value
  if native_label!=null:
   native_label.text=value
   refresh_contract()
func _init():
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 native_label=Label.new()
 native_label.add_theme_font_size_override("font_size",30)
 native_label.vertical_alignment=VERTICAL_ALIGNMENT_TOP
 native_label.clip_text=false
 add_child(native_label)
 clip_contents=false
 size_flags_vertical=Control.SIZE_SHRINK_CENTER
func configure(record:Dictionary,height:float,registry:RefCounted=null):
 source_record=record.duplicate(true)
 source_height=height
 if registry==null:registry=Fonts.shared()
 # Remove a previous override so failure cannot silently retain stale binding.
 native_label.remove_theme_font_override("font")
 binding=registry.bind_control(native_label,source_record)
 set_meta("source_font_status",binding.status)
 set_meta("source_font_guid",Fonts.font_guid(source_record))
 native_label.add_theme_font_size_override("font_size",int(record.get("m_fontSize",30)))
 refresh_contract()
func _get_minimum_size()->Vector2:return expected_min
func _notification(what):
 if what==NOTIFICATION_RESIZED and native_label!=null: place_native()
func reject(reason:String):
 contract={"ok":false,"reason":reason,"presentation":"native_fallback"}
 source_min=Vector2.ZERO
 expected_min=native_label.get_combined_minimum_size()
 update_minimum_size()
 layout_contract_changed.emit()
 place_native()
func refresh_contract():
 if source_record.is_empty():reject("unconfigured");return
 if Fonts.font_guid(source_record)!="8f586378b4e144a9851e7b34d9b748ee":reject("unverified_source_face");return
 if binding.get("font")==null:reject(str(binding.get("status","missing_binding")));return
 if TranslationServer.get_locale().get_slice("_",0) not in ["en","zh"]:reject("unverified_locale");return
 var rx=RegEx.new()
 rx.compile("^-?[0-9]+(?:/-?[0-9]+)?$")
 if rx.search(text)==null:reject("not_integer_stats");return
 for part in text.split("/"):
  if not part.is_valid_int() or part.to_int()<-2147483648 or part.to_int()>2147483647:reject("outside_source_int32");return
 var required={"m_TextWrappingMode":1,"m_enableAutoSizing":0,"m_fontSize":30,"m_fontWeight":400,"m_fontStyle":0,"m_overflowMode":0,"m_isOrthographic":1,"m_characterSpacing":0,"m_wordSpacing":0,"m_lineSpacing":0,"m_paragraphSpacing":0,"m_charWidthMaxAdj":0,"m_HorizontalAlignment":1,"m_VerticalAlignment":512,"m_ActiveFontFeatures":"6e72656b"}
 for key in required:
  if source_record.get(key)!=required[key]:reject("unsupported_source_"+key);return
 if source_height!=30:reject("unsupported_source_height");return
 var margin=source_record.get("m_margin")
 if not margin is Dictionary:reject("missing_source_margin");return
 for key in ["x","y","z","w"]:
  if margin.get(key)!=0:reject("unsupported_source_margin");return
 var normalized={"font_weight":400,"font_style":0,"word_wrap":0,"overflow_mode":0,"horizontal_alignment":1,"is_orthographic":true,"character_spacing":0,"word_spacing":0,"enable_kerning":true,"char_width_max_adjustment":0}
 # NoWrap belongs ONLY to GetPreferredWidth's infinite-margin request.
 var result=Measure.measure(text,normalized,binding.source_metrics,30)
 if not result.ok:reject(result.reason);return
 var preferred=float(int(result.width*100+1))/100.0
 var line=TextLine.new()
 line.add_string(text,native_label.get_theme_font("font"),30,TranslationServer.get_locale())
 var ts=TextServerManager.get_primary_interface()
 var pen=0.0
 var leftmost=INF
 var rightmost=-INF
 for glyph in ts.shaped_text_get_glyphs(line.get_rid()):
  var offset=ts.font_get_glyph_offset(glyph.font_rid,Vector2i(glyph.font_size,0),glyph.index)
  var extent=ts.font_get_glyph_size(glyph.font_rid,Vector2i(glyph.font_size,0),glyph.index)
  for repeat in glyph.repeat:
   leftmost=minf(leftmost,pen+glyph.offset.x+offset.x)
   rightmost=maxf(rightmost,pen+glyph.offset.x+offset.x+extent.x)
   pen+=glyph.advance
 # The verified adjacent64x30 icon draws a30-wide quad, inset17. Use glyph
 # rectangles (including padding), not assumed ink. Reserve1 unit as guard.
 if leftmost < -16 or rightmost > preferred+16:reject("native_glyph_neighbor_guard");return
 var face:Dictionary=binding.source_metrics.m_FaceInfo
 var baseline=source_height/2+(float(face.m_AscentLine)+float(face.m_DescentLine))*30/float(face.m_PointSize)*float(face.m_Scale)/2
 contract={"ok":true,"preferred_width":preferred,"baseline_down":baseline,"presentation":"native_glyphs_not_TMP_SDF"}
 source_min=Vector2(preferred,source_height)
 expected_min=source_min if group_source_enabled else native_label.get_combined_minimum_size()
 update_minimum_size()
 layout_contract_changed.emit()
 place_native()
func place_native():
 if native_label==null:return
 native_label.size=native_label.get_combined_minimum_size()
 native_label.position=Vector2.ZERO
 if contract.get("ok",false) and group_source_enabled:
  var line=TextLine.new()
  line.add_string(text,native_label.get_theme_font("font"),native_label.get_theme_font_size("font_size"))
  native_label.position.y=float(contract.baseline_down)-line.get_line_ascent()

func set_group_mode(enabled:bool):
 if group_source_enabled==enabled:return
 group_source_enabled=enabled
 expected_min=source_min if enabled and contract.get("ok",false) else native_label.get_combined_minimum_size()
 update_minimum_size()
 place_native()

static func source_height_from(value:Variant)->float:
 if not value is Dictionary:return 0.0
 var height=value.get("y")
 if height is int or height is float:return float(height)
 return 0.0
