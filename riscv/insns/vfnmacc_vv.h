// vfnmacc: vd[i] = -(vs1[i] * vs2[i]) - vd[i]
VI_VFP_VV_LOOP_BF16
({
  vd = f16_mulAdd(f16(vs2.v ^ F16_SIGN), vs1, f16(vd.v ^ F16_SIGN));
},
{
  vd = f32_mulAdd(f32(vs2.v ^ F32_SIGN), vs1, f32(vd.v ^ F32_SIGN));
},
{
  vd = f64_mulAdd(f64(vs2.v ^ F64_SIGN), vs1, f64(vd.v ^ F64_SIGN));
},
{
  bfloat16_t zero_bf16 = {0};
  vd = bf16_sub(zero_bf16, bf16_add(bf16_mul(vs1, vs2), vd));
})
