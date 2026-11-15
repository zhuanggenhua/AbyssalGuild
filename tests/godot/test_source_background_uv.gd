extends SceneTree
## Source-derived coordinate contract, not a Unity framebuffer oracle.
const Assets=preload("res://scripts/ui/visual_assets.gd")
var failures:=0
var checks:=0
func check(ok:bool, label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL: ",label)
func _init():
 var assets=Assets.new()
 var image=Image.create(16,16,false,Image.FORMAT_RGBA8)
 for y in range(16):
  for x in range(16):image.set_pixel(x,y,Color(x/15.0,y/15.0,((x*3+y*5)%16)/15.0,1))
 var bytes=image.get_data();assets.texture_cache.synthetic=ImageTexture.create_from_image(image)
 assets.manifest={"assets":{"synthetic":{"texture_importer":{"wrap_u":0,"wrap_v":0,"filter_mode":1,"mipmaps":1}}},"materials":{"ground":{"shader_reference":{"fileID":"10752","guid":"0000000000000000f000000000000000"},"textures":{"_MainTex":{"m_Texture":{"guid":"synthetic"},"m_Scale":{"x":1.7,"y":2.3},"m_Offset":{"x":0.13,"y":-0.27}}}}},"scenes":{"Test":{"scene_meshes":[{"file_id":"test","enabled":1,"mesh":{"fileID":"10209","guid":"0000000000000000e000000000000000"},"materials":[{"guid":"ground"}],"transform_chain":[{"m_LocalPosition":{"x":0,"y":-10,"z":0},"m_LocalRotation":{"x":0,"y":1,"z":0,"w":0},"m_LocalScale":{"x":10,"y":1,"z":10}}]}]}}}
 for st in [Vector4(1.7,2.3,.13,-.27),Vector4(-.65,1.25,-.31,.17),Vector4(20,20,0,0)]:
  var env=assets.manifest.materials.ground.textures._MainTex
  env.m_Scale={"x":st.x,"y":st.y};env.m_Offset={"x":st.z,"y":st.w}
  var group=assets.create_scene_background("Test");var n=group.get_child(0);var m=n.material_override
  var a=n.mesh.get_mesh_arrays()
  for i in a[Mesh.ARRAY_VERTEX].size():
   var p:Vector3=a[Mesh.ARRAY_VERTEX][i];var uv:Vector2=a[Mesh.ARRAY_TEX_UV][i]
   check(uv.is_equal_approx(Vector2((p.x+5)/10,(p.z+5)/10)),"native PlaneMesh UV function")
  for p in [Vector3(1.25,0,-2.5),Vector3(-3.1,0,1.7),Vector3(.45,0,-.85)]:
   # Corresponding source point is (x,y,-z), not unchanged p.
   var source_uv=Vector2((5-p.x)/10,(5+p.z)/10)
   var source_sample=source_uv*Vector2(st.x,st.y)+Vector2(st.z,st.w)
   var expected=Vector2(source_sample.x,1-source_sample.y)
   var native_uv=Vector2((p.x+5)/10,(p.z+5)/10)
   var actual=native_uv*Vector2(m.uv1_scale.x,m.uv1_scale.y)+Vector2(m.uv1_offset.x,m.uv1_offset.y)
   check(actual.is_equal_approx(expected),"scale/offset after geometry and PNG row origin")
   # CPU image observer only; asymmetric rows and columns reject double flips.
   var ex=Vector2i(int(fposmod(expected.x,1)*16),int(fposmod(expected.y,1)*16))
   var got=Vector2i(int(fposmod(actual.x,1)*16),int(fposmod(actual.y,1)*16))
   check(image.get_pixelv(ex)==image.get_pixelv(got),"asymmetric texture coordinate observer")
   if is_equal_approx(st.x,1.7):
    var old=native_uv*Vector2(st.x,st.y)+Vector2(st.z,st.w)
    var oldp=Vector2i(int(fposmod(old.x,1)*16),int(fposmod(old.y,1)*16))
    check(image.get_pixelv(oldp)!=image.get_pixelv(ex),"old unconverted ST is real negative control")
   check((n.transform*p).is_equal_approx(Vector3(-10*p.x,-10+p.y,-10*p.z)),"scene pose unchanged")
  check(m.albedo_texture.get_image().get_data().slice(0,bytes.size())==bytes,"base image not flipped")
  check(m.albedo_texture.get_image().has_mipmaps(),"mip fix retained")
  group.free()
 assets.manifest.scenes.Test.scene_meshes[0].mesh.fileID="10210"
 check(assets.create_scene_background("Test")==null,"unrelated built-in mesh remains unsupported, no UV rewrite")
 assets.manifest.scenes.Test.scene_meshes[0].mesh.fileID="10209"
 assets.manifest.materials.ground.shader_reference.fileID="99999"
 check(assets.create_scene_background("Test")==null,"unrelated shader remains unsupported, no UV rewrite")
 check(assets.texture_cache.synthetic.get_image().get_data()==bytes,"asset cache unchanged")
 print("Source background UV contract: ",checks," checks, ",failures," failures; no GPU/source screenshot claim")
 quit(1 if failures else 0)
