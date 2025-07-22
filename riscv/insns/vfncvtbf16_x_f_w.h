// vfncvtbf16.x.f.w vd, vs2, vm
VI_VFP_NCVT_BF16_TO_INT8(
  { vd = bf16_to_i8(vs2, softfloat_roundingMode, true); },    // BODY
  { require_extension(EXT_ZVFBFMIN); }                        // CHECK
)