extends SceneTree
const AudioDrain = preload("res://tests/godot/source_test_audio_drain.gd")
const Fonts=preload("res://scripts/ui/source_font_registry.gd")
var checks=0
func check(ok:bool):
 checks+=1
 assert(ok)
# Independent preferred-width oracle for admitted numeric strings, read only
# from private imported source tables. No copied glyph fixtures are shipped.
func preferred(text:String,metrics:Dictionary)->float:
 var chars={}
 var glyphs={}
 var pairs={}
 for c in metrics.m_CharacterTable:chars[int(c.m_Unicode)]=int(c.m_GlyphIndex)
 for g in metrics.m_GlyphTable:glyphs[int(g.m_Index)]=g
 for pair in metrics.m_FontFeatureTable.m_GlyphPairAdjustmentRecords:
  pairs["%d:%d"%[pair.m_FirstAdjustmentRecord.m_GlyphIndex,pair.m_SecondAdjustmentRecord.m_GlyphIndex]]=pair
 var sequence=[]
 for c in text:sequence.append(glyphs[chars[c.unicode_at(0)]])
 var scale=30.0/float(metrics.m_FaceInfo.m_PointSize)
 var pen=0.0
 var width=0.0
 for i in sequence.size():
  var g=sequence[i]
  var correction=0.0
  for side in [-1,1]:
   var j=i+side
   if j<0 or j>=sequence.size():continue
   var pair:Dictionary=pairs.get("%d:%d"%[sequence[mini(i,j)].m_Index,sequence[maxi(i,j)].m_Index],{})
   if not pair.is_empty():correction+=float(pair["m_FirstAdjustmentRecord" if side==1 else "m_SecondAdjustmentRecord"].m_GlyphValueRecord.m_XAdvance)
  width=maxf(width,pen+float(g.m_Metrics.m_HorizontalAdvance)*scale)
  pen+=(float(g.m_Metrics.m_HorizontalAdvance)+correction)*scale
 return float(int(width*100+1))/100.0
func _init():call_deferred("run")
func run():
 var board=load("res://scripts/ui/board.gd").new()
 board.options_path="user://stats-options.json"
 board.slot_root="user://stats-slots"
 board.legacy_paths.clear()
 root.add_child(board)
 for i in 4:await process_frame
 var audio_drain := AudioDrain.new()
 audio_drain.observe_music(board.feedback.music)
 board.session.start_new_game()
 board._enter_game()
 for i in 6:await process_frame
 board.set_process(false)
 board.set_physics_process(false)
 var metrics=Fonts.shared().resolve("8f586378b4e144a9851e7b34d9b748ee").source_metrics
 for locale in ["en","zh_CN"]:
  TranslationServer.set_locale(locale)
  for value in ["0","111","888","-12","100/200","999999"]:
   for c in board.stat_labels:c.text=value
   for i in 5:await process_frame
   check(board.stats_box.source_enabled)
   var pos=64.0
   var width=preferred(value,metrics)
   for c in board.stat_labels:
    check(c.group_source_enabled)
    check(absf(c.position.x-pos)<0.0001)
    check(absf(c.size.x-width)<0.0001 and c.size.y==30)
    check(absf(c.get_global_rect().get_center().y/board.source_hud.scale.y-55)<0.0001)
    var line=TextLine.new()
    line.add_string(c.text,c.native_label.get_theme_font("font"),30)
    var observed=c.native_label.get_global_rect().position.y/board.source_hud.scale.y+line.get_line_ascent()
    var face:Dictionary=metrics.m_FaceInfo
    var expected=55+(float(face.m_AscentLine)+float(face.m_DescentLine))*30/float(face.m_PointSize)/2
    check(absf(observed-expected)<0.0001)
    check(not c.clip_contents and not c.native_label.clip_text)
    pos+=width+64
  board.stat_labels[1].text="中文"
  for i in 5:await process_frame
  check(not board.stats_box.source_enabled)
  for c in board.stat_labels:check(not c.group_source_enabled)
  board.stat_labels[1].text="0"
  for i in 5:await process_frame
  check(board.stats_box.source_enabled)
 var registry=Fonts.new()
 registry.load_manifest()
 registry.manifest.fonts.clear()
 var label=board.stat_labels[0]
 label.configure(label.source_record,30,registry)
 label.text="100/200"
 for i in 5:await process_frame
 check(not board.stats_box.source_enabled)
 check(label.contract.reason=="missing_source_font_binding")
 check(not label.native_label.has_theme_font_override("font"))
 for c in board.stat_labels:check(not c.group_source_enabled)
 board.queue_free()
 await process_frame
 check(await audio_drain.wait_after_teardown(self))
 print("Source Stats imported layout: PASS (%d checks; no pixel claim)"%checks)
 quit()
