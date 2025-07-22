.section .rodata
.align 3
bf16_data:
  .hword 0x3F80  # 1.0 in BF16 format
  .hword 0x4000  # 2.0 in BF16 format  
  .hword 0xC000  # -2.0 in BF16 format
  .hword 0x4240  # 48.0 in BF16 format
  .hword 0x0000  # 0.0 in BF16 format
  .hword 0x4180  # 16.0 in BF16 format
  .hword 0xC180  # -16.0 in BF16 format
  .hword 0x427F  # 63.75 in BF16 format (close to INT8_MAX)

.section .bss
.align 3
int8_result:
  # 为8个 int8 结果预留空间
  .space 8

.text
.globl _start
_start:
  # --- 开启浮点和向量单元 ---
  csrr t1, mstatus

  # 一次性将 FS 和 VS 字段都设置为 'Initial' (01)
  # 0x2200 = (1 << 13) | (1 << 9)
  li t2, 0x2200
  or t1, t1, t2
  
  # 将修改后的值写回 mstatus
  csrw mstatus, t1
  # --- 单元已开启 ---

  # 我们要处理8个BF16元素
  li t0, 8
  
  # 设置向量配置 (vcfg):
  # 元素位宽 SEW = 16 bits (用于加载 BF16 数据)
  # 向量寄存器分组 LMUL = 1
  # 设置向量长度 (vl) 为 8
  vsetvli a0, t0, e16, m1, ta, ma

  # 从内存加载 BF16 数据到向量寄存器 v8
  la t1, bf16_data
  vle16.v v8, (t1)

  # --- 核心转换逻辑 (使用我们的新指令) ---

  # 1. 设置 SEW=8 为 vfncvtbf16 指令做准备
  #    该指令将 2*SEW (16-bit) 的 BF16 数据转换为 SEW (8-bit) 的有符号整数。
  #    vl 保持不变 (8)，因为我们还是要处理8个元素。
  #    v8 寄存器中的内容不变，但现在被 vfncvtbf16 解释为双倍宽度的源操作数。
  vsetvli a0, t0, e8, m1, ta, ma

  # 2. 转换: 直接将 BF16 向量 (v8) 转为 INT8 向量 (v10)
  #    手写机器码: vfncvtbf16.x.f.w v10, v8 (不使用掩码)
  #    编码: 0x480e5057 | (v10 << 7) | (v8 << 20)
  #    v10 = 10 (0xa), v8 = 8 (0x8)
  #    最终: 0x480e5057 | (10 << 7) | (8 << 20) = 0x480e5057 | 0x500 | 0x800000 = 0x488e5557
  #    设置第25位为1 (unmasked): 0x488e5557 | (1<<25) = 0x488e5557 | 0x2000000 = 0x4a8e5557
  vfncvtbf16.x.f.w v10, v8

  # --- 验证步骤 ---
  
  # 将最终的 INT8 结果 (v10) 存回内存，方便在调试器中观察
  la t1, int8_result
  vse8.v v10, (t1)

# 结束程序，进入一个无限循环，以便在调试器中检查寄存器状态
done:
  li a0, 0
  ebreak  # 使用 ebreak 而不是非法指令
  j done 