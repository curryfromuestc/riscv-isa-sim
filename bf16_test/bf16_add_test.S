# BF16向量加法测试
# 测试 vfadd.vv 指令在BF16模式下的功能

.section .rodata
.align 3

# BF16测试数据 - 第一组操作数
bf16_operand_a:
  .hword 0x3F80  # 1.0 in BF16
  .hword 0x4000  # 2.0 in BF16
  .hword 0x4040  # 3.0 in BF16
  .hword 0x4080  # 4.0 in BF16
  .hword 0x40A0  # 5.0 in BF16
  .hword 0x40C0  # 6.0 in BF16
  .hword 0x40E0  # 7.0 in BF16
  .hword 0x4100  # 8.0 in BF16

# BF16测试数据 - 第二组操作数
bf16_operand_b:
  .hword 0x40A0  # 5.0 in BF16
  .hword 0x4040  # 3.0 in BF16
  .hword 0x3F80  # 1.0 in BF16
  .hword 0x4000  # 2.0 in BF16
  .hword 0x4080  # 4.0 in BF16
  .hword 0x40C0  # 6.0 in BF16
  .hword 0x40E0  # 7.0 in BF16
  .hword 0x4100  # 8.0 in BF16

.section .bss
.align 3

# 结果存储区域
bf16_add_result:
  .space 16      # 8个BF16结果，每个2字节

.text
.globl _start
_start:
  # --- 初始化浮点和向量单元 ---
  csrr t1, mstatus
  li t2, 0x2200          # FS=01, VS=01 (Initial状态)
  or t1, t1, t2
  csrw mstatus, t1

  # --- 设置向量长度 ---
  li t0, 8               # 处理8个元素
  
  # 设置BF16模式：SEW=101(5) -> BF16模式（最高位=1表示BF16）
  # 虽然理论位宽是2^(5+3)=256，但实际操作16位BF16数据
  # vtype编码: [7]=vma, [6]=vta, [5:3]=SEW, [2:0]=LMUL  
  # BF16模式: SEW=101(5), LMUL=000(m1), vta=1, vma=1
  # 二进制: 11101000 = 0xE8
  li t1, 0xE8            # vtype值，SEW=5(BF16标识), LMUL=m1, vta=1, vma=1
  
  # 直接调用vsetvl系统调用来设置BF16模式
  # 这是一个临时方案，需要vsetvl支持SEW=5
  vsetvl a0, t0, t1

  # --- 加载BF16测试数据 ---
  la t1, bf16_operand_a
  vle16.v v8, (t1)       # 加载第一组操作数到v8

  la t1, bf16_operand_b
  vle16.v v9, (t1)       # 加载第二组操作数到v9

  # --- 执行BF16向量加法 ---
  # 注意：这需要vfadd.vv支持BF16模式(e256)
  # 如果BF16模式未启用，这将执行标准的FP16加法
  vfadd.vv v10, v8, v9   # v10 = v8 + v9 (BF16加法)

  # --- 存储结果 ---
  la t1, bf16_add_result
  vse16.v v10, (t1)

  # --- 测试完成 ---
  li a0, 0               # 设置返回码为0
  ebreak                 # 断点，便于调试

# 无限循环
done:
  j done

# =================================================================
# 预期结果：
# =================================================================
# 操作数A: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
# 操作数B: [5.0, 3.0, 1.0, 2.0, 4.0, 6.0, 7.0, 8.0]
# 预期结果: [6.0, 5.0, 4.0, 6.0, 9.0, 12.0, 14.0, 16.0]
#
# BF16格式预期结果：
# 6.0  -> 0x40C0
# 5.0  -> 0x40A0
# 4.0  -> 0x4080
# 6.0  -> 0x40C0
# 9.0  -> 0x4110
# 12.0 -> 0x4140
# 14.0 -> 0x4160
# 16.0 -> 0x4180 