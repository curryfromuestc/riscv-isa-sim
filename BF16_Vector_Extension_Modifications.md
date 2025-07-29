# RISC-V BF16 向量扩展修改总结

## 概述

本文档记录了在RISC-V Spike模拟器中实现BF16（Brain Floating Point 16）向量扩展的所有修改。该实现通过使用SEW（Standard Element Width）字段的特殊编码来支持BF16操作：

- **核心设计理念**：当SEW=5（101二进制）时，虽然理论计算得到的`vsew=2^(5+3)=256`，但实际操作的是16位BF16数据
- **BF16模式标识**：`vsew == 256` 在代码中作为BF16模式的标识符

## 文件修改详情

### 1. `riscv/v_ext_macros.h`

#### 1.1 修改 `VI_CHECK_STORE` 宏
**位置**: 行128-138  
**问题**: BF16模式下`vle16.v`指令失败，因为`vemul`计算错误  
**解决方案**: 添加BF16特殊处理逻辑

```c
#define VI_CHECK_STORE(elt_width, is_mask_ldst) \
  require_vector(false); \
  reg_t veew = is_mask_ldst ? 1 : sizeof(elt_width##_t) * 8; \
  /* BF16特殊处理：当SEW=256且操作16位数据时，使用有效SEW=16 */ \
  reg_t effective_sew = (P.VU.vsew == 256 && veew == 16) ? 16 : P.VU.vsew; \
  float vemul = is_mask_ldst ? 1 : ((float)veew / effective_sew * P.VU.vflmul); \
  reg_t emul = vemul < 1 ? 1 : vemul; \
  require(vemul >= 0.125 && vemul <= 8); \
  require_align(insn.rd(), vemul); \
  require_noover(insn.rd(), P.VU.vflmul, insn.rs1(), 1);
```

#### 1.2 重构向量浮点循环宏
**问题**: 原始设计混合了3参数和4参数宏，导致编译错误  
**解决方案**: 分离普通FP和BF16支持

**恢复原始3参数宏**:
```c
#define VI_VFP_VV_LOOP(BODY16, BODY32, BODY64) \
  VI_CHECK_SSS(true); \
  VI_VFP_LOOP_BASE \
  switch (P.VU.vsew) { \
    case e16: { \
      VFP_VV_PARAMS(16); \
      BODY16; \
      set_fp_exceptions; \
      break; \
    } \
    case e32: { \
      VFP_VV_PARAMS(32); \
      BODY32; \
      set_fp_exceptions; \
      break; \
    } \
    case e64: { \
      VFP_VV_PARAMS(64); \
      BODY64; \
      set_fp_exceptions; \
      break; \
    } \
    default: \
      require(0); \
      break; \
  }; \
  DEBUG_RVV_FP_VV; \
  VI_VFP_LOOP_END
```

**新增专用BF16宏**:
```c
#define VI_VFP_VV_LOOP_BF16(BODY16, BODY32, BODY64, BODY_BF16) \
  VI_CHECK_SSS(true); \
  VI_VFP_BF16_LOOP_BASE \
  switch (P.VU.vsew) { \
    case e16: { \
      VFP_VV_PARAMS(16); \
      BODY16; \
      set_fp_exceptions; \
      break; \
    } \
    case e32: { \
      VFP_VV_PARAMS(32); \
      BODY32; \
      set_fp_exceptions; \
      break; \
    } \
    case e64: { \
      VFP_VV_PARAMS(64); \
      BODY64; \
      set_fp_exceptions; \
      break; \
    } \
    case e256: { \
      VFP_BF16_VV_PARAMS(); \
      BODY_BF16; \
      set_fp_exceptions; \
      break; \
    } \
    default: \
      require(0); \
      break; \
  }; \
  DEBUG_RVV_FP_VV; \
  VI_VFP_LOOP_END
```

#### 1.3 修改 `VI_VFP_BF16_COMMON` 宏
**问题**: 原始宏不允许`vsew == e256`，导致非法指令异常  
**解决方案**: 添加对`vsew == e256`的支持

```c
#define VI_VFP_BF16_COMMON \
  require_fp; \
  require((P.VU.vsew == e16 && p->extension_enabled(EXT_ZVFBFWMA)) || \
          (P.VU.vsew == e256)); \
  require_vector(true); \
  require(STATE.frm->read() < 0x5); \
  reg_t UNUSED vl = P.VU.vl->read(); \
  reg_t UNUSED rd_num = insn.rd(); \
  reg_t UNUSED rs1_num = insn.rs1(); \
  reg_t UNUSED rs2_num = insn.rs2();
```

### 2. `riscv/vector_unit.cc`

#### 2.1 修改 `set_vl` 函数
**位置**: 行30-50  
**问题**: BF16模式下`vlmax`计算和`vill`检查使用错误的SEW值  
**解决方案**: 引入`effective_sew`概念

```c
void vectorUnit_t::set_vl(int rd, int rs1, reg_t reqVL, reg_t newType) {
  // ... 其他代码 ...
  
  vsew = 1 << (extract64(newType, 3, 3) + 3);
  vflmul = new_vlmul >= 0 ? 1 << new_vlmul : 1.0 / (1 << -new_vlmul);
  
  // BF16特殊处理：SEW=5表示BF16模式，虽然vsew=256但实际操作16位数据
  reg_t effective_sew_for_vlmax = (vsew == 256) ? 16 : vsew;
  vlmax = (VLEN/effective_sew_for_vlmax) * vflmul;
  vta = extract64(newType, 6, 1);
  vma = extract64(newType, 7, 1);

  // BF16特殊处理：SEW=5表示BF16模式，虽然vsew=256但实际操作16位数据
  reg_t effective_sew_for_check = (vsew == 256) ? 16 : vsew;
  
  vill = !(vflmul >= 0.125 && vflmul <= 8)
         || effective_sew_for_check > std::min(vflmul, 1.0f) * ELEN
         || (newType >> 8) != 0
         || (rd == 0 && rs1 == 0 && old_vlmax != vlmax);

  // ... 其他代码 ...
}
```

### 3. 指令文件修改

以下指令文件从`VI_VFP_VV_LOOP`改为`VI_VFP_VV_LOOP_BF16`以支持BF16操作：

#### 3.1 `riscv/insns/vfadd_vv.h`
```c
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
```

#### 3.2 `riscv/insns/vfsub_vv.h`
```c
// vfsub.vv vd, vs2, vs1
VI_VFP_VV_LOOP_BF16
({
  vd = f16_sub(vs2, vs1);
},
{
  vd = f32_sub(vs2, vs1);
},
{
  vd = f64_sub(vs2, vs1);
},
{
  vd = bf16_sub(vs2, vs1);
})
```

#### 3.3 `riscv/insns/vfmul_vv.h`
```c
// vfmul.vv vd, vs1, vs2, vm
VI_VFP_VV_LOOP_BF16
({
  vd = f16_mul(vs1, vs2);
},
{
  vd = f32_mul(vs1, vs2);
},
{
  vd = f64_mul(vs1, vs2);
},
{
  vd = bf16_mul(vs1, vs2);
})
```

#### 3.4 `riscv/insns/vfmadd_vv.h`
```c
// vfmadd: vd[i] = +(vd[i] * vs1[i]) + vs2[i]
VI_VFP_VV_LOOP_BF16
({
  vd = f16_mulAdd(vd, vs1, vs2);
},
{
  vd = f32_mulAdd(vd, vs1, vs2);
},
{
  vd = f64_mulAdd(vd, vs1, vs2);
},
{
  vd = bf16_mulAdd(vd, vs1, vs2);
})
```

#### 3.5 `riscv/insns/vfmacc_vv.h`
```c
// vfmacc.vv vd, rs1, vs2, vm    # vd[i] = +(vs2[i] * vs1[i]) + vd[i]
VI_VFP_VV_LOOP_BF16
({
  vd = f16_mulAdd(vs1, vs2, vd);
},
{
  vd = f32_mulAdd(vs1, vs2, vd);
},
{
  vd = f64_mulAdd(vs1, vs2, vd);
},
{
  vd = bf16_mulAdd(vs1, vs2, vd);
})
```

#### 3.6 `riscv/insns/vfmsac_vv.h`
```c
// vfmsac: vd[i] = +(vs1[i] * vs2[i]) - vd[i]
VI_VFP_VV_LOOP_BF16
({
  vd = f16_mulAdd(vs1, vs2, f16(vd.v ^ F16_SIGN));
},
{
  vd = f32_mulAdd(vs1, vs2, f32(vd.v ^ F32_SIGN));
},
{
  vd = f64_mulAdd(vs1, vs2, f64(vd.v ^ F64_SIGN));
},
{
  vd = bf16_sub(bf16_mul(vs1, vs2), vd);
})
```

#### 3.7 `riscv/insns/vfmsub_vv.h`
```c
// vfmsub: vd[i] = +(vd[i] * vs1[i]) - vs2[i]
VI_VFP_VV_LOOP_BF16
({
  vd = f16_mulAdd(vd, vs1, f16(vs2.v ^ F16_SIGN));
},
{
  vd = f32_mulAdd(vd, vs1, f32(vs2.v ^ F32_SIGN));
},
{
  vd = f64_mulAdd(vd, vs1, f64(vs2.v ^ F64_SIGN));
},
{
  vd = bf16_sub(bf16_mul(vd, vs1), vs2);
})
```

#### 3.8 `riscv/insns/vfnmacc_vv.h`
```c
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
```

#### 3.9 `riscv/insns/vfmin_vv.h`
```c
// vfmin vd, vs2, vs1
VI_VFP_VV_LOOP_BF16
({
  vd = f16_min(vs2, vs1);
},
{
  vd = f32_min(vs2, vs1);
},
{
  vd = f64_min(vs2, vs1);
},
{
  vd = bf16_min(vs2, vs1);
})
```

#### 3.10 `riscv/insns/vfmax_vv.h`
```c
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
```

### 4. 测试文件

#### 4.1 `bf16_test/bf16_add_test.S`
创建了BF16向量加法的汇编测试程序：

```assembly
.section .text
.globl _start

_start:
    # 测试数据（BF16格式）
    # 1.0 in BF16: 0x3F80 
    # 2.0 in BF16: 0x4000
    # 3.0 in BF16: 0x4040 
    # 4.0 in BF16: 0x4080
    
    la t1, test_data
    li t0, 8        # 设置向量长度
    
    # 设置BF16模式：SEW=101(5) -> BF16模式（最高位=1表示BF16）
    # 二进制: 11101000 = 0xE8
    li t1, 0xE8     # vtype值，SEW=5(BF16标识), LMUL=m1, vta=1, vma=1
    
    # 直接调用vsetvl系统调用来设置BF16模式
    vsetvl a0, t0, t1
    
    # 重新设置数据地址
    la t1, test_data
    
    # 加载第一个向量 (1.0, 2.0, 3.0, 4.0)
    vle16.v v8, (t1)
    
    # 加载第二个向量 (1.0, 2.0, 3.0, 4.0) 
    vle16.v v9, (t1)  
    
    # BF16向量加法: v10 = v8 + v9
    vfadd.vv v10, v8, v9
    
    # 存储结果到内存
    vse16.v v10, (t1)
    
    # 程序结束
    li a0, 0
    ebreak

.section .data
.align 4
test_data:
    .word 0x40003F80  # 1.0f_bf16, 2.0f_bf16
    .word 0x40804040  # 3.0f_bf16, 4.0f_bf16
```

#### 4.2 `bf16_test/test.lds`
链接脚本确保程序加载到正确的内存地址：

```lds
OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  
  .text : {
    *(.text)
  }
  
  .rodata : {
    *(.rodata)
  }
  
  .bss : {
    *(.bss)
  }
}
```

## 技术细节

### SEW编码方案
- **SEW=0 (000)**: 8位 (2^(0+3) = 8)
- **SEW=1 (001)**: 16位 FP16 (2^(1+3) = 16) 
- **SEW=2 (010)**: 32位 (2^(2+3) = 32)
- **SEW=3 (011)**: 64位 (2^(3+3) = 64)
- **SEW=5 (101)**: 16位 BF16模式 (理论256位，实际16位)

### vtype寄存器编码 (BF16模式)
```
vtype = 0xE8 (11101000)
- bit[7] vma = 1 (mask agnostic)
- bit[6] vta = 1 (tail agnostic)  
- bit[5:3] SEW = 101 (5, BF16模式)
- bit[2:0] LMUL = 000 (m1)
```

### 编译和测试命令
```bash
# 编译测试程序
cd bf16_test
riscv64-unknown-elf-gcc -march=rv64gcv -mabi=lp64d -nostartfiles -nostdlib -T test.lds -o bf16_add_test bf16_add_test.S

# 运行测试
cd ../build
./spike -d bf16_test/bf16_add_test
```

## 验证结果

测试程序成功执行完整流程：
1. ✅ `vsetvl` - 设置BF16向量模式
2. ✅ `vle16.v` - BF16向量加载  
3. ✅ `vfadd.vv` - BF16向量加法
4. ✅ `vse16.v` - BF16向量存储
5. ✅ 程序正常结束

## 支持的BF16指令

以下向量浮点指令已支持BF16模式：
- `vfadd.vv` - 向量加法
- `vfsub.vv` - 向量减法  
- `vfmul.vv` - 向量乘法
- `vfmadd.vv` - 向量乘加 (vd = vd * vs1 + vs2)
- `vfmacc.vv` - 向量乘累加 (vd = vs1 * vs2 + vd)
- `vfmsac.vv` - 向量乘减 (vd = vs1 * vs2 - vd)
- `vfmsub.vv` - 向量乘减 (vd = vd * vs1 - vs2)  
- `vfnmacc.vv` - 向量负乘累加 (vd = -(vs1 * vs2) - vd)
- `vfmin.vv` - 向量最小值
- `vfmax.vv` - 向量最大值

## 设计优势

1. **最小化修改范围**: 只修改需要BF16支持的核心指令，避免大面积更改
2. **向后兼容**: 保持原有FP16/FP32/FP64指令的正常工作
3. **清晰的抽象**: 通过`effective_sew`概念统一处理BF16的特殊性
4. **可扩展性**: 新的BF16指令可以轻松使用`VI_VFP_VV_LOOP_BF16`宏添加

## 注意事项

1. BF16模式使用`vsew=256`作为内部标识，但实际操作16位数据
2. 需要确保softfloat库支持相应的BF16函数（如`bf16_add`、`bf16_mul`等）
3. 除法指令`vfdiv.vv`暂不支持BF16，会保持原有的3参数宏
4. 其他不需要BF16支持的浮点指令维持原状，避免不必要的复杂性 