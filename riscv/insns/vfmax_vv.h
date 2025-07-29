// vfmax
VI_VFP_VV_LOOP_BF16
({
  vd = f16_max(vs2, vs1);
},
{
  vd = f32_max(vs2, vs1);
},
{
  vd = f64_max(vs2, vs1);
},
{
  vd = bf16_max(vs2, vs1);
})
