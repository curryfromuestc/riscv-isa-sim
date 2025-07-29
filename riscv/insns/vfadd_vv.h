// vfadd.vv vd, vs2, vs1
VI_VFP_VV_LOOP_BF16
({
  vd = f16_add(vs1, vs2);
},
{
  vd = f32_add(vs1, vs2);
},
{
  vd = f64_add(vs1, vs2);
},
{
  vd = bf16_add(vs1, vs2);
})
