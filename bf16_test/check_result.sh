#!/bin/bash

# 运行程序并在ebreak处停止，然后检查内存
{
    echo "until pc 0x80000038"  # 运行直到ebreak
    echo "mem 0x80000050 8"     # 检查int8_result的内容
    echo "reg v10"              # 查看v10寄存器的内容
    echo "q"                    # 退出
} | ../build/spike --isa=rv64gcv_zvfbfmin -d bf16_to_int8_test.elf 