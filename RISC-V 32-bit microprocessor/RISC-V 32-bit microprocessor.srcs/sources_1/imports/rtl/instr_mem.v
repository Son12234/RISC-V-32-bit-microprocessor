`timescale 1ns / 1ps                       // Đơn vị thời gian mô phỏng = 1ns, độ chính xác = 1ps
//==============================================================================
// Module : instr_mem  (bộ nhớ lệnh - ROM đọc bất đồng bộ)
// - Chương trình được nhúng THẲNG trong file này (khối initial), nên không cần
//   file .hex/.mem và không bị lỗi "không tìm thấy file" khi mô phỏng trong Vivado.
// - Mã máy được dịch bằng trình dịch GNU thật (riscv64-unknown-elf-as -march=rv32i);
//   mỗi dòng có chú thích địa chỉ, lệnh hợp ngữ và ý nghĩa.
// - PROGRAM = 0 : chương trình kiểm thử toàn bộ tập lệnh RV32I (dùng cho testbench)
//   PROGRAM = 1 : chương trình demo Fibonacci (dùng khi nạp xuống board)
// - Muốn chạy chương trình khác: thay các dòng mem[...] bên dưới bằng mã máy mới.
// - Địa chỉ vượt kích thước ROM sẽ bị "quấn vòng"; ô chưa dùng chứa NOP.
//==============================================================================
module instr_mem #(
    parameter PROGRAM   = 0,           // Chọn chương trình (0 = kiểm thử ISA, 1 = demo Fibonacci)
    parameter ADDR_BITS = 8            // Số bit chỉ số từ: 2^8 = 256 lệnh (1 KiB)
) (
    input  wire [31:0] addr,           // Địa chỉ byte của lệnh cần nạp (chính là PC)
    output wire [31:0] instr           // Lệnh 32 bit đọc ra
);

    localparam DEPTH = 1 << ADDR_BITS;                         // Số lệnh tối đa trong ROM

    reg [31:0] mem [0:DEPTH-1];                          // Mảng lưu các lệnh 32 bit (ROM đọc bất đồng bộ -> Vivado tự dùng LUT)

    integer i;                                                 // Biến chạy cho vòng lặp khởi tạo

    initial begin                                              // Nạp chương trình lúc bắt đầu mô phỏng / cấu hình FPGA
        for (i = 0; i < DEPTH; i = i + 1)                      // Duyệt toàn bộ ROM
            mem[i] = 32'h0000_0013;                            // Điền NOP (addi x0,x0,0) để không có giá trị X

        if (PROGRAM == 0) begin
            //------------------------------------------------------------------
            // PROGRAM 0 : kiểm thử toàn bộ RV32I (245 lệnh)
            // Mỗi kết quả được ghi vào RAM[0x000...] để testbench kiểm tra.
            // Vòng lặp kết thúc "jal x0, L_done" nằm tại địa chỉ 0x3D0.
            //------------------------------------------------------------------
            mem[0] = 32'h00500093;   // 0x000: addi x1, x0, 5             | x1 = 5
            mem[1] = 32'hFFD00113;   // 0x004: addi x2, x0, -3            | x2 = -3 (0xFFFFFFFD)
            mem[2] = 32'h123451B7;   // 0x008: lui x3, 0x12345            | x3 = 0x12345000
            mem[3] = 32'h67818193;   // 0x00C: addi x3, x3, 0x678         | x3 = 0x12345678 (phu thuoc du lieu lien ke -> forwarding)
            mem[4] = 32'h00302023;   // 0x010: sw x3, 0(x0)               | ghi ket qua 'LUI+ADDI' vao RAM[0x000]
            mem[5] = 32'h00001217;   // 0x014: auipc x4, 1                | x4 = PC + 0x1000
            mem[6] = 32'h00402223;   // 0x018: sw x4, 4(x0)               | ghi ket qua 'AUIPC' vao RAM[0x004]
            mem[7] = 32'h00012293;   // 0x01C: slti x5, x2, 0             | x5 = (-3 < 0) co dau = 1
            mem[8] = 32'h00502423;   // 0x020: sw x5, 8(x0)               | ghi ket qua 'SLTI' vao RAM[0x008]
            mem[9] = 32'h00013313;   // 0x024: sltiu x6, x2, 0            | x6 = (0xFFFFFFFD < 0) khong dau = 0
            mem[10] = 32'h00602623;   // 0x028: sw x6, 12(x0)              | ghi ket qua 'SLTIU' vao RAM[0x00C]
            mem[11] = 32'h00F0C393;   // 0x02C: xori x7, x1, 15            | x7 = 5 ^ 15 = 10
            mem[12] = 32'h00702823;   // 0x030: sw x7, 16(x0)              | ghi ket qua 'XORI' vao RAM[0x010]
            mem[13] = 32'h0300E413;   // 0x034: ori x8, x1, 48             | x8 = 5 | 0x30 = 0x35
            mem[14] = 32'h00802A23;   // 0x038: sw x8, 20(x0)              | ghi ket qua 'ORI' vao RAM[0x014]
            mem[15] = 32'h0FF1F493;   // 0x03C: andi x9, x3, 255           | x9 = 0x78
            mem[16] = 32'h00902C23;   // 0x040: sw x9, 24(x0)              | ghi ket qua 'ANDI' vao RAM[0x018]
            mem[17] = 32'h00409513;   // 0x044: slli x10, x1, 4            | x10 = 5 << 4 = 80
            mem[18] = 32'h00A02E23;   // 0x048: sw x10, 28(x0)             | ghi ket qua 'SLLI' vao RAM[0x01C]
            mem[19] = 32'h01C15593;   // 0x04C: srli x11, x2, 28           | x11 = 0xFFFFFFFD >> 28 = 0xF
            mem[20] = 32'h02B02023;   // 0x050: sw x11, 32(x0)             | ghi ket qua 'SRLI' vao RAM[0x020]
            mem[21] = 32'h40115613;   // 0x054: srai x12, x2, 1            | x12 = -3 >>> 1 = 0xFFFFFFFE
            mem[22] = 32'h02C02223;   // 0x058: sw x12, 36(x0)             | ghi ket qua 'SRAI' vao RAM[0x024]
            mem[23] = 32'h002086B3;   // 0x05C: add x13, x1, x2            | 5 + (-3) = 2
            mem[24] = 32'h02D02423;   // 0x060: sw x13, 40(x0)             | ghi ket qua 'ADD' vao RAM[0x028]
            mem[25] = 32'h40208733;   // 0x064: sub x14, x1, x2            | 5 - (-3) = 8
            mem[26] = 32'h02E02623;   // 0x068: sw x14, 44(x0)             | ghi ket qua 'SUB' vao RAM[0x02C]
            mem[27] = 32'h001097B3;   // 0x06C: sll x15, x1, x1            | 5 << 5 = 160
            mem[28] = 32'h02F02823;   // 0x070: sw x15, 48(x0)             | ghi ket qua 'SLL' vao RAM[0x030]
            mem[29] = 32'h00112833;   // 0x074: slt x16, x2, x1            | -3 < 5 (co dau) = 1
            mem[30] = 32'h03002A23;   // 0x078: sw x16, 52(x0)             | ghi ket qua 'SLT' vao RAM[0x034]
            mem[31] = 32'h001138B3;   // 0x07C: sltu x17, x2, x1           | 0xFFFFFFFD < 5 (khong dau) = 0
            mem[32] = 32'h03102C23;   // 0x080: sw x17, 56(x0)             | ghi ket qua 'SLTU' vao RAM[0x038]
            mem[33] = 32'h0030C933;   // 0x084: xor x18, x1, x3            | 5 ^ 0x12345678
            mem[34] = 32'h03202E23;   // 0x088: sw x18, 60(x0)             | ghi ket qua 'XOR' vao RAM[0x03C]
            mem[35] = 32'h0011D9B3;   // 0x08C: srl x19, x3, x1            | 0x12345678 >> 5
            mem[36] = 32'h05302023;   // 0x090: sw x19, 64(x0)             | ghi ket qua 'SRL' vao RAM[0x040]
            mem[37] = 32'h40115AB3;   // 0x094: sra x21, x2, x1            | -3 >>> 5 = -1
            mem[38] = 32'h05502223;   // 0x098: sw x21, 68(x0)             | ghi ket qua 'SRA' vao RAM[0x044]
            mem[39] = 32'h0080EB33;   // 0x09C: or x22, x1, x8             | 5 | 0x35
            mem[40] = 32'h05602423;   // 0x0A0: sw x22, 72(x0)             | ghi ket qua 'OR' vao RAM[0x048]
            mem[41] = 32'h0081FBB3;   // 0x0A4: and x23, x3, x8            | 0x12345678 & 0x35
            mem[42] = 32'h05702623;   // 0x0A8: sw x23, 76(x0)             | ghi ket qua 'AND' vao RAM[0x04C]
            mem[43] = 32'h80000C37;   // 0x0AC: lui x24, 0x80000           | x24 = 0x80000000
            mem[44] = 32'hFFFC0C13;   // 0x0B0: addi x24, x24, -1          | x24 = 0x7FFFFFFF (so duong lon nhat)
            mem[45] = 32'h001C0C93;   // 0x0B4: addi x25, x24, 1           | x25 = 0x80000000 (tran so, quay vong)
            mem[46] = 32'h05902823;   // 0x0B8: sw x25, 80(x0)             | ghi ket qua 'ADDI overflow wrap' vao RAM[0x050]
            mem[47] = 32'h40100D33;   // 0x0BC: sub x26, x0, x1            | x26 = 0 - 5 = -5
            mem[48] = 32'h05A02A23;   // 0x0C0: sw x26, 84(x0)             | ghi ket qua 'SUB negative' vao RAM[0x054]
            mem[49] = 32'h018CADB3;   // 0x0C4: slt x27, x25, x24          | 0x80000000 < 0x7FFFFFFF co dau = 1
            mem[50] = 32'h05B02C23;   // 0x0C8: sw x27, 88(x0)             | ghi ket qua 'SLT signed edge' vao RAM[0x058]
            mem[51] = 32'h018CBE33;   // 0x0CC: sltu x28, x25, x24         | 0x80000000 < 0x7FFFFFFF khong dau = 0
            mem[52] = 32'h05C02E23;   // 0x0D0: sw x28, 92(x0)             | ghi ket qua 'SLTU unsigned edge' vao RAM[0x05C]
            mem[53] = 32'h01F00F93;   // 0x0D4: addi x31, x0, 31           | x31 = 31
            mem[54] = 32'h41FCDEB3;   // 0x0D8: sra x29, x25, x31          | 0x80000000 >>> 31 = 0xFFFFFFFF
            mem[55] = 32'h07D02023;   // 0x0DC: sw x29, 96(x0)             | ghi ket qua 'SRA by 31' vao RAM[0x060]
            mem[56] = 32'h41FCDE93;   // 0x0E0: srai x29, x25, 31          | 0x80000000 >>> 31 = 0xFFFFFFFF
            mem[57] = 32'h07D02223;   // 0x0E4: sw x29, 100(x0)            | ghi ket qua 'SRAI by 31' vao RAM[0x064]
            mem[58] = 32'h02500F93;   // 0x0E8: addi x31, x0, 37           | x31 = 37 (chi 5 bit thap = 5 duoc dung)
            mem[59] = 32'h01F09EB3;   // 0x0EC: sll x29, x1, x31           | 5 << (37 & 31) = 160
            mem[60] = 32'h07D02423;   // 0x0F0: sw x29, 104(x0)            | ghi ket qua 'SLL shamt masked' vao RAM[0x068]
            mem[61] = 32'hFFFFFEB7;   // 0x0F4: lui x29, 0xFFFFF           | x29 = 0xFFFFF000
            mem[62] = 32'h07D02623;   // 0x0F8: sw x29, 108(x0)            | ghi ket qua 'LUI max' vao RAM[0x06C]
            mem[63] = 32'hFFF0BE93;   // 0x0FC: sltiu x29, x1, -1          | 5 < 0xFFFFFFFF khong dau = 1
            mem[64] = 32'h07D02823;   // 0x100: sw x29, 112(x0)            | ghi ket qua 'SLTIU imm -1' vao RAM[0x070]
            mem[65] = 32'h00203EB3;   // 0x104: sltu x29, x0, x2           | 0 < 0xFFFFFFFD khong dau = 1
            mem[66] = 32'h07D02A23;   // 0x108: sw x29, 116(x0)            | ghi ket qua 'SLTU 0 < nonzero' vao RAM[0x074]
            mem[67] = 32'h00A00093;   // 0x10C: addi x1, x0, 10            | x1 = 10
            mem[68] = 32'h00508113;   // 0x110: addi x2, x1, 5             | x2 = 15  (x1 cach 1 lenh -> forward EX/MEM)
            mem[69] = 32'h001101B3;   // 0x114: add x3, x2, x1             | x3 = 25  (x2 cach 1, x1 cach 2 -> forward EX/MEM + MEM/WB)
            mem[70] = 32'h00318233;   // 0x118: add x4, x3, x3             | x4 = 50  (ca hai toan hang cach 1 lenh)
            mem[71] = 32'h06402C23;   // 0x11C: sw x4, 120(x0)             | ghi ket qua 'FWD EX/MEM + MEM/WB' vao RAM[0x078]
            mem[72] = 32'h00100313;   // 0x120: addi x6, x0, 1             | x6 = 1
            mem[73] = 32'h00000013;   // 0x124: nop                        | cach 1
            mem[74] = 32'h00000013;   // 0x128: nop                        | cach 2
            mem[75] = 32'h006303B3;   // 0x12C: add x7, x6, x6             | x6 cach 3 lenh -> bypass trong reg_file, x7 = 2
            mem[76] = 32'h06702E23;   // 0x130: sw x7, 124(x0)             | ghi ket qua 'regfile write-through' vao RAM[0x07C]
            mem[77] = 32'h03700013;   // 0x134: addi x0, x0, 55            | ghi vao x0 phai bi bo qua
            mem[78] = 32'h00100413;   // 0x138: addi x8, x0, 1             | x0 van = 0 -> x8 = 1 (forward sai se cho 56)
            mem[79] = 32'h08802023;   // 0x13C: sw x8, 128(x0)             | ghi ket qua 'x0 not forwarded' vao RAM[0x080]
            mem[80] = 32'h000004B3;   // 0x140: add x9, x0, x0             | x9 = 0
            mem[81] = 32'h08902223;   // 0x144: sw x9, 132(x0)             | ghi ket qua 'x0 reads zero' vao RAM[0x084]
            mem[82] = 32'h03200513;   // 0x148: addi x10, x0, 50           | x10 = 50
            mem[83] = 32'h2CA02023;   // 0x14C: sw x10, 704(x0)            | RAM[0x2C0] = 50 (du lieu store vua tinh xong -> forward)
            mem[84] = 32'h2C002583;   // 0x150: lw x11, 704(x0)            | x11 = 50 (doc ngay sau khi ghi cung dia chi)
            mem[85] = 32'h00158613;   // 0x154: addi x12, x11, 1           | dung ngay x11 -> LOAD-USE: stall 1 chu ky, x12 = 51
            mem[86] = 32'h08C02423;   // 0x158: sw x12, 136(x0)            | ghi ket qua 'LOAD-USE stall' vao RAM[0x088]
            mem[87] = 32'h2C002683;   // 0x15C: lw x13, 704(x0)            | x13 = 50
            mem[88] = 32'h2CD02223;   // 0x160: sw x13, 708(x0)            | du lieu store phu thuoc LOAD ngay truoc -> stall + forward
            mem[89] = 32'h2C402703;   // 0x164: lw x14, 708(x0)            | x14 = 50
            mem[90] = 32'h08E02623;   // 0x168: sw x14, 140(x0)            | ghi ket qua 'LOAD then STORE data' vao RAM[0x08C]
            mem[91] = 32'h80F180B7;   // 0x16C: lui x1, 0x80F18            | x1 = 0x80F18000
            mem[92] = 32'hF8508093;   // 0x170: addi x1, x1, -123          | x1 = 0x80F17F85  (byte: 85 7F F1 80)
            mem[93] = 32'h20102023;   // 0x174: sw x1, 512(x0)             | RAM[0x200] = 0x80F17F85
            mem[94] = 32'h20002103;   // 0x178: lw x2, 512(x0)             | LW
            mem[95] = 32'h08202823;   // 0x17C: sw x2, 144(x0)             | ghi ket qua 'LW' vao RAM[0x090]
            mem[96] = 32'h20000183;   // 0x180: lb x3, 512(x0)             | byte 0 = 0x85 -> mo rong dau 0xFFFFFF85
            mem[97] = 32'h08302A23;   // 0x184: sw x3, 148(x0)             | ghi ket qua 'LB byte0 (neg)' vao RAM[0x094]
            mem[98] = 32'h20100203;   // 0x188: lb x4, 513(x0)             | byte 1 = 0x7F -> 0x0000007F
            mem[99] = 32'h08402C23;   // 0x18C: sw x4, 152(x0)             | ghi ket qua 'LB byte1 (pos)' vao RAM[0x098]
            mem[100] = 32'h20200283;   // 0x190: lb x5, 514(x0)             | byte 2 = 0xF1 -> 0xFFFFFFF1
            mem[101] = 32'h08502E23;   // 0x194: sw x5, 156(x0)             | ghi ket qua 'LB byte2 (neg)' vao RAM[0x09C]
            mem[102] = 32'h20300303;   // 0x198: lb x6, 515(x0)             | byte 3 = 0x80 -> 0xFFFFFF80
            mem[103] = 32'h0A602023;   // 0x19C: sw x6, 160(x0)             | ghi ket qua 'LB byte3 (neg)' vao RAM[0x0A0]
            mem[104] = 32'h20004383;   // 0x1A0: lbu x7, 512(x0)            | byte 0 khong dau = 0x85
            mem[105] = 32'h0A702223;   // 0x1A4: sw x7, 164(x0)             | ghi ket qua 'LBU byte0' vao RAM[0x0A4]
            mem[106] = 32'h20304403;   // 0x1A8: lbu x8, 515(x0)            | byte 3 khong dau = 0x80
            mem[107] = 32'h0A802423;   // 0x1AC: sw x8, 168(x0)             | ghi ket qua 'LBU byte3' vao RAM[0x0A8]
            mem[108] = 32'h20001483;   // 0x1B0: lh x9, 512(x0)             | nua tu thap = 0x7F85 -> 0x00007F85
            mem[109] = 32'h0A902623;   // 0x1B4: sw x9, 172(x0)             | ghi ket qua 'LH low (pos)' vao RAM[0x0AC]
            mem[110] = 32'h20201503;   // 0x1B8: lh x10, 514(x0)            | nua tu cao = 0x80F1 -> 0xFFFF80F1
            mem[111] = 32'h0AA02823;   // 0x1BC: sw x10, 176(x0)            | ghi ket qua 'LH high (neg)' vao RAM[0x0B0]
            mem[112] = 32'h20205583;   // 0x1C0: lhu x11, 514(x0)           | nua tu cao khong dau = 0x000080F1
            mem[113] = 32'h0AB02A23;   // 0x1C4: sw x11, 180(x0)            | ghi ket qua 'LHU high' vao RAM[0x0B4]
            mem[114] = 32'h20005603;   // 0x1C8: lhu x12, 512(x0)           | nua tu thap khong dau = 0x00007F85
            mem[115] = 32'h0AC02C23;   // 0x1CC: sw x12, 184(x0)            | ghi ket qua 'LHU low' vao RAM[0x0B8]
            mem[116] = 32'h01100693;   // 0x1D0: addi x13, x0, 0x11         | x13 = 0x11
            mem[117] = 32'h20D00223;   // 0x1D4: sb x13, 516(x0)            | ghi byte 0 cua tu RAM[0x204]
            mem[118] = 32'h02200693;   // 0x1D8: addi x13, x0, 0x22         | x13 = 0x22
            mem[119] = 32'h20D002A3;   // 0x1DC: sb x13, 517(x0)            | ghi byte 1 cua tu RAM[0x204]
            mem[120] = 32'h03300693;   // 0x1E0: addi x13, x0, 0x33         | x13 = 0x33
            mem[121] = 32'h20D00323;   // 0x1E4: sb x13, 518(x0)            | ghi byte 2 cua tu RAM[0x204]
            mem[122] = 32'h04400693;   // 0x1E8: addi x13, x0, 0x44         | x13 = 0x44
            mem[123] = 32'h20D003A3;   // 0x1EC: sb x13, 519(x0)            | ghi byte 3 cua tu RAM[0x204]
            mem[124] = 32'h20402703;   // 0x1F0: lw x14, 516(x0)            | doc lai tu = 0x44332211
            mem[125] = 32'h0AE02E23;   // 0x1F4: sw x14, 188(x0)            | ghi ket qua 'SB x4 then LW' vao RAM[0x0BC]
            mem[126] = 32'h0000C7B7;   // 0x1F8: lui x15, 0xC               | x15 = 0x0000C000
            mem[127] = 32'hEEF78793;   // 0x1FC: addi x15, x15, -273        | x15 = 0x0000BEEF
            mem[128] = 32'h20F01423;   // 0x200: sh x15, 520(x0)            | ghi nua tu thap cua RAM[0x208]
            mem[129] = 32'h20F01523;   // 0x204: sh x15, 522(x0)            | ghi nua tu cao cua RAM[0x208]
            mem[130] = 32'h20802803;   // 0x208: lw x16, 520(x0)            | doc lai tu = 0xBEEFBEEF
            mem[131] = 32'h0D002023;   // 0x20C: sw x16, 192(x0)            | ghi ket qua 'SH x2 then LW' vao RAM[0x0C0]
            mem[132] = 32'h07A00693;   // 0x210: addi x13, x0, 0x7A         | x13 = 0x7A
            mem[133] = 32'h20D000A3;   // 0x214: sb x13, 513(x0)            | ghi de 1 byte vao RAM[0x200]: cac byte khac khong doi
            mem[134] = 32'h20002883;   // 0x218: lw x17, 512(x0)            | doc lai = 0x80F17A85
            mem[135] = 32'h0D102223;   // 0x21C: sw x17, 196(x0)            | ghi ket qua 'SB partial overwrite' vao RAM[0x0C4]
            mem[136] = 32'h21000913;   // 0x220: addi x18, x0, 528          | x18 = 528
            mem[137] = 32'hFF092983;   // 0x224: lw x19, -16(x18)           | offset am: dia chi 512 -> 0x80F17A85
            mem[138] = 32'h0D302423;   // 0x228: sw x19, 200(x0)            | ghi ket qua 'LW negative offset' vao RAM[0x0C8]
            mem[139] = 32'h00000A13;   // 0x22C: addi x20, x0, 0            | x20 = diem so A (cong dan bit khi nhanh dung, test 0..10)
            mem[140] = 32'h00000E93;   // 0x230: addi x29, x0, 0            | x29 = diem so B (test 11..13)
            mem[141] = 32'h00700093;   // 0x234: addi x1, x0, 7             | x1 = 7
            mem[142] = 32'h00700113;   // 0x238: addi x2, x0, 7             | x2 = 7
            mem[143] = 32'h00900193;   // 0x23C: addi x3, x0, 9             | x3 = 9
            mem[144] = 32'hFFF00213;   // 0x240: addi x4, x0, -1            | x4 = -1 (0xFFFFFFFF)
            mem[145] = 32'h00208663;   // 0x244: beq x1, x2, L_br0          | BEQ phai RE nhanh
            mem[146] = 32'h31402023;   // 0x248: sw x20, 768(x0)            | [nhanh sai] lenh STORE nay phai bi huy (flush)
            mem[147] = 32'h001F0F13;   // 0x24C: addi x30, x30, 1           | [nhanh sai] phai bi huy (flush)
            // ---- nhan L_br0 ----
            mem[148] = 32'h001A0A13;   // 0x250: addi x20, x20, 1           | dung -> cong bit 0
            mem[149] = 32'h00308463;   // 0x254: beq x1, x3, L_br1          | BEQ KHONG duoc re nhanh
            mem[150] = 32'h002A0A13;   // 0x258: addi x20, x20, 2           | di thang -> cong bit 1
            // ---- nhan L_br1 ----
            mem[151] = 32'h00309663;   // 0x25C: bne x1, x3, L_br2          | BNE phai RE nhanh
            mem[152] = 32'h001F0F13;   // 0x260: addi x30, x30, 1           | [nhanh sai] phai bi huy (flush)
            mem[153] = 32'h001F0F13;   // 0x264: addi x30, x30, 1           | [nhanh sai] phai bi huy (flush)
            // ---- nhan L_br2 ----
            mem[154] = 32'h004A0A13;   // 0x268: addi x20, x20, 4           | dung -> cong bit 2
            mem[155] = 32'h00209463;   // 0x26C: bne x1, x2, L_br3          | BNE KHONG duoc re nhanh
            mem[156] = 32'h008A0A13;   // 0x270: addi x20, x20, 8           | di thang -> cong bit 3
            // ---- nhan L_br3 ----
            mem[157] = 32'h00124663;   // 0x274: blt x4, x1, L_br4          | BLT phai RE nhanh
            mem[158] = 32'h001F0F13;   // 0x278: addi x30, x30, 1           | [nhanh sai] phai bi huy (flush)
            mem[159] = 32'h001F0F13;   // 0x27C: addi x30, x30, 1           | [nhanh sai] phai bi huy (flush)
            // ---- nhan L_br4 ----
            mem[160] = 32'h010A0A13;   // 0x280: addi x20, x20, 16          | dung -> cong bit 4
            mem[161] = 32'h0040C463;   // 0x284: blt x1, x4, L_br5          | BLT KHONG duoc re nhanh
            mem[162] = 32'h020A0A13;   // 0x288: addi x20, x20, 32          | di thang -> cong bit 5
            // ---- nhan L_br5 ----
            mem[163] = 32'h0040D663;   // 0x28C: bge x1, x4, L_br6          | BGE phai RE nhanh
            mem[164] = 32'h001F0F13;   // 0x290: addi x30, x30, 1           | [nhanh sai] phai bi huy (flush)
            mem[165] = 32'h001F0F13;   // 0x294: addi x30, x30, 1           | [nhanh sai] phai bi huy (flush)
            // ---- nhan L_br6 ----
            mem[166] = 32'h040A0A13;   // 0x298: addi x20, x20, 64          | dung -> cong bit 6
            mem[167] = 32'h00125463;   // 0x29C: bge x4, x1, L_br7          | BGE KHONG duoc re nhanh
            mem[168] = 32'h080A0A13;   // 0x2A0: addi x20, x20, 128         | di thang -> cong bit 7
            // ---- nhan L_br7 ----
            mem[169] = 32'h0040E663;   // 0x2A4: bltu x1, x4, L_br8         | BLTU phai RE nhanh
            mem[170] = 32'h001F0F13;   // 0x2A8: addi x30, x30, 1           | [nhanh sai] phai bi huy (flush)
            mem[171] = 32'h001F0F13;   // 0x2AC: addi x30, x30, 1           | [nhanh sai] phai bi huy (flush)
            // ---- nhan L_br8 ----
            mem[172] = 32'h100A0A13;   // 0x2B0: addi x20, x20, 256         | dung -> cong bit 8
            mem[173] = 32'h00126463;   // 0x2B4: bltu x4, x1, L_br9         | BLTU KHONG duoc re nhanh
            mem[174] = 32'h200A0A13;   // 0x2B8: addi x20, x20, 512         | di thang -> cong bit 9
            // ---- nhan L_br9 ----
            mem[175] = 32'h00127663;   // 0x2BC: bgeu x4, x1, L_br10        | BGEU phai RE nhanh
            mem[176] = 32'h001F0F13;   // 0x2C0: addi x30, x30, 1           | [nhanh sai] phai bi huy (flush)
            mem[177] = 32'h001F0F13;   // 0x2C4: addi x30, x30, 1           | [nhanh sai] phai bi huy (flush)
            // ---- nhan L_br10 ----
            mem[178] = 32'h400A0A13;   // 0x2C8: addi x20, x20, 1024        | dung -> cong bit 10
            mem[179] = 32'h0040F463;   // 0x2CC: bgeu x1, x4, L_br11        | BGEU KHONG duoc re nhanh
            mem[180] = 32'h001E8E93;   // 0x2D0: addi x29, x29, 1           | di thang -> cong bit 11
            // ---- nhan L_br11 ----
            mem[181] = 32'h0020D663;   // 0x2D4: bge x1, x2, L_br12         | BGE phai RE nhanh
            mem[182] = 32'h001F0F13;   // 0x2D8: addi x30, x30, 1           | [nhanh sai] phai bi huy (flush)
            mem[183] = 32'h001F0F13;   // 0x2DC: addi x30, x30, 1           | [nhanh sai] phai bi huy (flush)
            // ---- nhan L_br12 ----
            mem[184] = 32'h002E8E93;   // 0x2E0: addi x29, x29, 2           | dung -> cong bit 12
            mem[185] = 32'h0020F663;   // 0x2E4: bgeu x1, x2, L_br13        | BGEU phai RE nhanh
            mem[186] = 32'h001F0F13;   // 0x2E8: addi x30, x30, 1           | [nhanh sai] phai bi huy (flush)
            mem[187] = 32'h001F0F13;   // 0x2EC: addi x30, x30, 1           | [nhanh sai] phai bi huy (flush)
            // ---- nhan L_br13 ----
            mem[188] = 32'h004E8E93;   // 0x2F0: addi x29, x29, 4           | dung -> cong bit 13
            mem[189] = 32'h0D402623;   // 0x2F4: sw x20, 204(x0)            | ghi ket qua 'BRANCH score A (tests 0-10)' vao RAM[0x0CC]
            mem[190] = 32'h0DD02823;   // 0x2F8: sw x29, 208(x0)            | ghi ket qua 'BRANCH score B (tests 11-13)' vao RAM[0x0D0]
            mem[191] = 32'h00208663;   // 0x2FC: beq x1, x2, L_b2b_a        | nhanh re thu nhat
            mem[192] = 32'h001F0F13;   // 0x300: addi x30, x30, 1           | [nhanh sai]
            mem[193] = 32'h001F0F13;   // 0x304: addi x30, x30, 1           | [nhanh sai]
            // ---- nhan L_b2b_a ----
            mem[194] = 32'h00208663;   // 0x308: beq x1, x2, L_b2b_b        | nhanh re thu hai nam ngay tai dich nhanh thu nhat
            mem[195] = 32'h001F0F13;   // 0x30C: addi x30, x30, 1           | [nhanh sai]
            mem[196] = 32'h001F0F13;   // 0x310: addi x30, x30, 1           | [nhanh sai]
            // ---- nhan L_b2b_b ----
            mem[197] = 32'h00100A93;   // 0x314: addi x21, x0, 1            | x21 = 1
            mem[198] = 32'h0D502A23;   // 0x318: sw x21, 212(x0)            | ghi ket qua 'back-to-back taken branches' vao RAM[0x0D4]
            mem[199] = 32'h00300293;   // 0x31C: addi x5, x0, 3             | x5 = 3
            mem[200] = 32'h00300313;   // 0x320: addi x6, x0, 3             | x6 = 3
            mem[201] = 32'h00028393;   // 0x324: addi x7, x5, 0             | x7 = 3 (vua tinh, cach 1 lenh so voi nhanh)
            mem[202] = 32'h00638663;   // 0x328: beq x7, x6, L_fwdbr        | x7 forward tu EX/MEM, x6 forward tu MEM/WB
            mem[203] = 32'h001F0F13;   // 0x32C: addi x30, x30, 1           | [nhanh sai]
            mem[204] = 32'h001F0F13;   // 0x330: addi x30, x30, 1           | [nhanh sai]
            // ---- nhan L_fwdbr ----
            mem[205] = 32'h00100B13;   // 0x334: addi x22, x0, 1            | x22 = 1
            mem[206] = 32'h0D602C23;   // 0x338: sw x22, 216(x0)            | ghi ket qua 'forward into branch compare' vao RAM[0x0D8]
            mem[207] = 32'h03200813;   // 0x33C: addi x16, x0, 50           | x16 = 50
            mem[208] = 32'h2C002783;   // 0x340: lw x15, 704(x0)            | x15 = 50
            mem[209] = 32'h01078663;   // 0x344: beq x15, x16, L_ldbr       | nhanh dung ngay ket qua LOAD -> stall 1 chu ky roi moi so sanh
            mem[210] = 32'h001F0F13;   // 0x348: addi x30, x30, 1           | [nhanh sai]
            mem[211] = 32'h001F0F13;   // 0x34C: addi x30, x30, 1           | [nhanh sai]
            // ---- nhan L_ldbr ----
            mem[212] = 32'h00100B93;   // 0x350: addi x23, x0, 1            | x23 = 1
            mem[213] = 32'h0D702E23;   // 0x354: sw x23, 220(x0)            | ghi ket qua 'branch after LOAD' vao RAM[0x0DC]
            mem[214] = 32'h00000293;   // 0x358: addi x5, x0, 0             | tong = 0
            mem[215] = 32'h00100313;   // 0x35C: addi x6, x0, 1             | i = 1
            mem[216] = 32'h00B00393;   // 0x360: addi x7, x0, 11            | gioi han = 11
            // ---- nhan L_loop ----
            mem[217] = 32'h006282B3;   // 0x364: add x5, x5, x6             | tong += i
            mem[218] = 32'h00130313;   // 0x368: addi x6, x6, 1             | i++
            mem[219] = 32'hFE731CE3;   // 0x36C: bne x6, x7, L_loop         | lap lai den khi i == 11 (nhanh nguoc, re 9 lan)
            mem[220] = 32'h0E502023;   // 0x370: sw x5, 224(x0)             | ghi ket qua 'LOOP sum 1..10 = 55' vao RAM[0x0E0]
            mem[221] = 32'h00C00B6F;   // 0x374: jal x22, L_jal_t           | nhay toi L_jal_t, x22 = PC + 4
            mem[222] = 32'h001F0F13;   // 0x378: addi x30, x30, 1           | [nhanh sai]
            mem[223] = 32'h001F0F13;   // 0x37C: addi x30, x30, 1           | [nhanh sai]
            // ---- nhan L_jal_t ----
            mem[224] = 32'h0F602223;   // 0x380: sw x22, 228(x0)            | ghi ket qua 'JAL link address' vao RAM[0x0E4]
            mem[225] = 32'h00000B97;   // 0x384: auipc x23, 0               | x23 = PC cua lenh nay (A)
            mem[226] = 32'h011B8B93;   // 0x388: addi x23, x23, 17          | x23 = A + 17 (bit 0 = 1: JALR phai xoa bit nay)
            mem[227] = 32'h000B8C67;   // 0x38C: jalr x24, 0(x23)           | nhay toi A + 16, x24 = PC + 4
            mem[228] = 32'h001F0F13;   // 0x390: addi x30, x30, 1           | [nhanh sai]
            // ---- nhan L_jalr_t ----
            mem[229] = 32'h0F802423;   // 0x394: sw x24, 232(x0)            | ghi ket qua 'JALR link address' vao RAM[0x0E8]
            mem[230] = 32'h00000D17;   // 0x398: auipc x26, 0               | x26 = PC cua lenh nay (B)
            mem[231] = 32'h018D0D13;   // 0x39C: addi x26, x26, 24          | x26 = B + 24
            mem[232] = 32'hFF8D0DE7;   // 0x3A0: jalr x27, -8(x26)          | nhay toi (B + 24 - 8) = B + 16, x27 = PC + 4
            mem[233] = 32'h001F0F13;   // 0x3A4: addi x30, x30, 1           | [nhanh sai]
            // ---- nhan L_jalr_t2 ----
            mem[234] = 32'h0FB02623;   // 0x3A8: sw x27, 236(x0)            | ghi ket qua 'JALR with imm' vao RAM[0x0EC]
            mem[235] = 32'h00600513;   // 0x3AC: addi x10, x0, 6            | doi so ham = 6
            mem[236] = 32'h00C000EF;   // 0x3B0: jal x1, F_double           | goi ham, x1 = dia chi quay ve
            mem[237] = 32'h0EA02823;   // 0x3B4: sw x10, 240(x0)            | ghi ket qua 'CALL/RET double(6)=12' vao RAM[0x0F0]
            mem[238] = 32'h00C0006F;   // 0x3B8: jal x0, F_end              | nhay qua than ham
            // ---- nhan F_double ----
            mem[239] = 32'h00A50533;   // 0x3BC: add x10, x10, x10          | x10 = 2 * x10
            mem[240] = 32'h00008067;   // 0x3C0: jalr x0, 0(x1)             | return
            // ---- nhan F_end ----
            mem[241] = 32'h0FE02A23;   // 0x3C4: sw x30, 244(x0)            | ghi ket qua 'wrong-path flag (must be 0)' vao RAM[0x0F4]
            mem[242] = 32'h30002F83;   // 0x3C8: lw x31, 768(x0)            | doc RAM[0x300]: lenh STORE nhanh sai khong duoc ghi
            mem[243] = 32'h0FF02C23;   // 0x3CC: sw x31, 248(x0)            | ghi ket qua 'wrong-path store (must be 0)' vao RAM[0x0F8]
            // ---- nhan L_done ----
            mem[244] = 32'h0000006F;   // 0x3D0: jal x0, L_done             | vong lap vo han: ket thuc chuong trinh
        end else begin
            //------------------------------------------------------------------
            // PROGRAM 1 : demo Fibonacci (11 lệnh)
            // x5 = số vòng, x6/x7 = Fibonacci, x10 = giá trị đọc lại từ RAM.
            //------------------------------------------------------------------
            mem[0] = 32'h00000293;   // 0x000: addi x5, x0, 0             | x5 = bo dem vong lap = 0
            mem[1] = 32'h00000313;   // 0x004: addi x6, x0, 0             | x6 = a = F(0) = 0
            mem[2] = 32'h00100393;   // 0x008: addi x7, x0, 1             | x7 = b = F(1) = 1
            // ---- nhan L_loop ----
            mem[3] = 32'h00730E33;   // 0x00C: add x28, x6, x7            | x28 = a + b
            mem[4] = 32'h00038313;   // 0x010: addi x6, x7, 0             | a = b
            mem[5] = 32'h000E0393;   // 0x014: addi x7, x28, 0            | b = a + b
            mem[6] = 32'h00128293;   // 0x018: addi x5, x5, 1             | dem vong++
            mem[7] = 32'h00602023;   // 0x01C: sw x6, 0(x0)               | ghi a vao RAM[0]
            mem[8] = 32'h00002503;   // 0x020: lw x10, 0(x0)              | doc lai vao x10 (xem bang cong tat)
            mem[9] = 32'h00050593;   // 0x024: addi x11, x10, 0           | x11 = x10 (load-use -> stall 1 chu ky)
            mem[10] = 32'hFE5FF06F;   // 0x028: jal x0, L_loop             | lap vo han
        end
    end

    assign instr = mem[addr[ADDR_BITS+1:2]];                   // Đọc bất đồng bộ: chỉ số từ = địa chỉ byte / 4

endmodule                                                      // Kết thúc module instr_mem
