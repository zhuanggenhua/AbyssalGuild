extends SceneTree
const D=preload("res://scripts/ui/card_interaction_descriptors.gd")
const Catalog=preload("res://scripts/model/catalog.gd")
var checks=0
var failures=0
func check(v:bool,s:String):
 checks+=1
 if not v:failures+=1;printerr("FAIL ",s)
func _init():
 # Numeric outputs from the matching original runtime, not self-derived labels.
 for row in [[0x4113ffff,"9.2"],[0x41140000,"9.3"],[0x41140001,"9.3"],[0x41159999,"9.3"],[0x4115999a,"9.4"],[0x4115999b,"9.4"],[0x3eb33332,"0.4"],[0x3eb33333,"0.4"],[0x3eb33334,"0.4"],[0x40a7ffff,"5.3"],[0x40a80000,"5.3"],[0x40a80001,"5.3"],[0,"0.0"],[0x80000000,"0.0"],[0x43340000,"180.0"]]:
  var bytes=PackedByteArray();bytes.resize(4);bytes.encode_u32(0,row[0])
  check(D._single_f1(bytes.decode_float(0))==row[1],"provider Single F1 control %s"%str(row[0]))
 var c=Catalog.new();c.configure({})
 check(D._remaining_text(c,10,.75,9.25)=="9.2","unknown catalog unchanged")
 c.data.provenance={"source_commit":"a11a89b04cea8370476f2559b639bb9b4cbc08d8"}
 check(D._remaining_text(c,10,.75,9.25)=="9.3","source quarter-tick counterexample")
 check(D._remaining_text(c,8,2.75,5.25)=="5.2","unverified duration unchanged")
 check(D._remaining_text(c,10,-1,11)=="11.0","negative progress fallback")
 check(D._remaining_text(c,10,11,0)=="0.0","overshoot fallback")
 check(D._remaining_text(c,10,NAN,0)=="0.0","invalid progress fallback")
 var before=JSON.stringify(c.data)
 for i in 10:D._remaining_text(c,10,.75,9.25)
 check(before==JSON.stringify(c.data),"catalog is read-only")
 print("Source craft F1: ",checks," checks, ",failures," failures")
 quit(0 if failures==0 else 1)
