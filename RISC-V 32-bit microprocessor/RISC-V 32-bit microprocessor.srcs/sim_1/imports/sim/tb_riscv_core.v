`timescale 1ns / 1ps                       // Đơn vị thời gian mô phỏng = 1ns, độ chính xác = 1ps
//==============================================================================
// Testbench : tb_riscv_core  (tự kiểm tra, in PASS / FAIL)
// Quy trình :
//   1. Tạo clock 100 MHz, giữ reset vài chu kỳ rồi thả.
//   2. CPU chạy chương trình kiểm thử trong instr_mem (PROGRAM = 0) cho tới khi
//      PC tới vòng lặp kết thúc (DONE_PC), chờ thêm vài chu kỳ cho pipeline rỗng.
//   3. So sánh 64 kết quả trong RAM dữ liệu và 32 thanh ghi với giá trị
//      mong đợi. Các giá trị này lấy từ một mô hình tham chiếu RV32I viết riêng
//      (độc lập với RTL), chạy trên đúng mã máy của chương trình.
//   4. Giám sát tín hiệu X/Z trên các thanh ghi pipeline mỗi chu kỳ.
// Kết quả cuối cùng: "*** ALL TESTS PASSED ***" hoặc "*** TEST FAILED ***".
//==============================================================================
module tb_riscv_core;

    localparam CLK_PERIOD = 10;                    // Chu kỳ clock = 10ns (100 MHz)
    localparam [31:0] DONE_PC = 32'h000003D0;    // Địa chỉ vòng lặp kết thúc "jal x0, L_done"
    localparam MAX_CYCLES = 5000;                  // Giới hạn thời gian chạy (chống treo)
    localparam INSTR_COUNT = 243;           // Số lệnh thực thi (theo mô hình tham chiếu) tới DONE_PC

    reg         clk          = 1'b0;               // Tín hiệu clock
    reg         rst          = 1'b1;               // Tín hiệu reset (bắt đầu ở mức 1)
    reg         en           = 1'b1;               // Clock-enable luôn bật khi mô phỏng
    reg  [4:0]  dbg_reg_addr = 5'd0;               // Số thanh ghi cần đọc qua cổng debug
    wire [31:0] dbg_reg_data;                      // Giá trị thanh ghi đọc được
    wire [31:0] dbg_pc;                            // PC hiện tại

    integer pass_cnt = 0;                          // Số phép kiểm tra đạt
    integer fail_cnt = 0;                          // Số phép kiểm tra sai
    integer x_cnt    = 0;                          // Số lần phát hiện tín hiệu X/Z
    integer cycle    = 0;                          // Đếm chu kỳ clock kể từ lúc thả reset
    integer cycles_done = 0;                       // Số chu kỳ khi PC tới DONE_PC
    integer i;                                     // Biến chạy

    reg [31:0] exp_reg [0:31];                     // Giá trị mong đợi của 32 thanh ghi

    // ---- Thiết bị cần kiểm tra (DUT) ----
    riscv_core #(.PROGRAM(0)) dut (
        .clk          (clk),
        .rst          (rst),
        .en           (en),
        .dbg_reg_addr (dbg_reg_addr),
        .dbg_reg_data (dbg_reg_data),
        .dbg_pc       (dbg_pc)
    );

    // ---- Tạo clock ----
    always #(CLK_PERIOD/2) clk = ~clk;             // Đảo clock mỗi nửa chu kỳ

    // ---- Đếm chu kỳ sau khi thả reset ----
    always @(posedge clk) begin
        if (!rst) cycle <= cycle + 1;              // Chỉ đếm khi không reset
    end

    // ---- Giám sát tín hiệu X/Z mỗi chu kỳ (kiểm tra "lỗi tín hiệu") ----
    always @(negedge clk) begin
        if (!rst) begin
            if ((^{dut.pc, dut.ifid_instr, dut.idex_rs1_data, dut.idex_rs2_data, dut.idex_imm,
                   dut.ex_rs1_val, dut.ex_rs2_val, dut.ex_alu_result, dut.exmem_alu_result,
                   dut.exmem_store_data, dut.mem_rdata, dut.memwb_alu_result, dut.memwb_rdata,
                   dut.wb_data}) === 1'bx) begin
                x_cnt = x_cnt + 1;                                             // Ghi nhận lỗi X/Z
                if (x_cnt <= 5)
                    $display("[X-ERROR] t=%0t: phat hien X/Z trong pipeline (PC=0x%08h)", $time, dut.pc);
            end
        end
    end

    // ---- Task: kiểm tra 1 ô nhớ dữ liệu (đọc trực tiếp 4 làn byte của RAM) ----
    task check_mem;
        input integer slot;                        // Chỉ số từ trong RAM (địa chỉ byte = slot*4)
        input [31:0]  expected;                    // Giá trị mong đợi
        input [8*32-1:0] name;                     // Tên phép kiểm tra (chuỗi)
        reg [31:0] actual;                         // Giá trị thực đọc được
        reg [11:0] baddr;                          // Địa chỉ byte (12 bit) chỉ để in cho gọn
        begin
            baddr = slot * 4;                      // Đổi chỉ số từ sang địa chỉ byte
            actual = {dut.u_dmem.mem3[slot], dut.u_dmem.mem2[slot],
                      dut.u_dmem.mem1[slot], dut.u_dmem.mem0[slot]};     // Ghép 4 làn byte thành từ 32 bit
            if (actual === expected) begin
                pass_cnt = pass_cnt + 1;
                $display("[PASS] %0s: RAM[0x%03h] = 0x%08h", name, baddr, actual);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("[FAIL] %0s: RAM[0x%03h] mong doi 0x%08h, thuc te 0x%08h", name, baddr, expected, actual);
            end
        end
    endtask

    // ---- Task: kiểm tra 1 thanh ghi qua cổng debug ----
    task check_reg;
        input integer idx;                         // Số thứ tự thanh ghi
        input [31:0]  expected;                    // Giá trị mong đợi
        begin
            dbg_reg_addr = idx[4:0];               // Chọn thanh ghi
            #1;                                    // Chờ 1ns cho tín hiệu tổ hợp ổn định
            if (dbg_reg_data === expected) begin
                pass_cnt = pass_cnt + 1;
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("[FAIL] x%0d mong doi 0x%08h, thuc te 0x%08h", idx, expected, dbg_reg_data);
            end
        end
    endtask

    // ---- Chương trình kiểm tra chính ----
    initial begin
`ifdef DUMP_VCD
        $dumpfile("tb_riscv_core.vcd");            // Xuất file sóng (chỉ khi biên dịch với -DDUMP_VCD)
        $dumpvars(0, tb_riscv_core);
`endif
        exp_reg[0] = 32'h00000000;
        exp_reg[1] = 32'h000003B4;
        exp_reg[2] = 32'h00000007;
        exp_reg[3] = 32'h00000009;
        exp_reg[4] = 32'hFFFFFFFF;
        exp_reg[5] = 32'h00000037;
        exp_reg[6] = 32'h0000000B;
        exp_reg[7] = 32'h0000000B;
        exp_reg[8] = 32'h00000080;
        exp_reg[9] = 32'h00007F85;
        exp_reg[10] = 32'h0000000C;
        exp_reg[11] = 32'h000080F1;
        exp_reg[12] = 32'h00007F85;
        exp_reg[13] = 32'h0000007A;
        exp_reg[14] = 32'h44332211;
        exp_reg[15] = 32'h00000032;
        exp_reg[16] = 32'h00000032;
        exp_reg[17] = 32'h80F17A85;
        exp_reg[18] = 32'h00000210;
        exp_reg[19] = 32'h80F17A85;
        exp_reg[20] = 32'h000007FF;
        exp_reg[21] = 32'h00000001;
        exp_reg[22] = 32'h00000378;
        exp_reg[23] = 32'h00000395;
        exp_reg[24] = 32'h00000390;
        exp_reg[25] = 32'h80000000;
        exp_reg[26] = 32'h000003B0;
        exp_reg[27] = 32'h000003A4;
        exp_reg[28] = 32'h00000000;
        exp_reg[29] = 32'h00000007;
        exp_reg[30] = 32'h00000000;
        exp_reg[31] = 32'h00000000;
        $display("==============================================================");
        $display(" TESTBENCH RISC-V RV32I - PIPELINE 5 TANG");
        $display("==============================================================");

        repeat (4) @(posedge clk);                 // Giữ reset 4 chu kỳ
        #1 rst = 1'b0;                             // Thả reset sau cạnh clock (tránh đua tín hiệu)

        // Chờ CPU chạy tới vòng lặp kết thúc (hoặc hết thời gian)
        while ((dbg_pc !== DONE_PC) && (cycle < MAX_CYCLES)) @(posedge clk);
        cycles_done = cycle;

        if (dbg_pc !== DONE_PC) begin
            fail_cnt = fail_cnt + 1;
            $display("[FAIL] TIMEOUT: PC = 0x%08h sau %0d chu ky, chua toi DONE_PC", dbg_pc, cycle);
        end

        repeat (12) @(posedge clk);                // Chờ pipeline xả hết các lệnh đang chạy dở
        #1;

        $display("--- Kiem tra ket qua trong RAM du lieu ---");
        check_mem(0, 32'h12345678, "LUI+ADDI");
        check_mem(1, 32'h00001014, "AUIPC");
        check_mem(2, 32'h00000001, "SLTI");
        check_mem(3, 32'h00000000, "SLTIU");
        check_mem(4, 32'h0000000A, "XORI");
        check_mem(5, 32'h00000035, "ORI");
        check_mem(6, 32'h00000078, "ANDI");
        check_mem(7, 32'h00000050, "SLLI");
        check_mem(8, 32'h0000000F, "SRLI");
        check_mem(9, 32'hFFFFFFFE, "SRAI");
        check_mem(10, 32'h00000002, "ADD");
        check_mem(11, 32'h00000008, "SUB");
        check_mem(12, 32'h000000A0, "SLL");
        check_mem(13, 32'h00000001, "SLT");
        check_mem(14, 32'h00000000, "SLTU");
        check_mem(15, 32'h1234567D, "XOR");
        check_mem(16, 32'h0091A2B3, "SRL");
        check_mem(17, 32'hFFFFFFFF, "SRA");
        check_mem(18, 32'h00000035, "OR");
        check_mem(19, 32'h00000030, "AND");
        check_mem(20, 32'h80000000, "ADDI overflow wrap");
        check_mem(21, 32'hFFFFFFFB, "SUB negative");
        check_mem(22, 32'h00000001, "SLT signed edge");
        check_mem(23, 32'h00000000, "SLTU unsigned edge");
        check_mem(24, 32'hFFFFFFFF, "SRA by 31");
        check_mem(25, 32'hFFFFFFFF, "SRAI by 31");
        check_mem(26, 32'h000000A0, "SLL shamt masked");
        check_mem(27, 32'hFFFFF000, "LUI max");
        check_mem(28, 32'h00000001, "SLTIU imm -1");
        check_mem(29, 32'h00000001, "SLTU 0 < nonzero");
        check_mem(30, 32'h00000032, "FWD EX/MEM + MEM/WB");
        check_mem(31, 32'h00000002, "regfile write-through");
        check_mem(32, 32'h00000001, "x0 not forwarded");
        check_mem(33, 32'h00000000, "x0 reads zero");
        check_mem(34, 32'h00000033, "LOAD-USE stall");
        check_mem(35, 32'h00000032, "LOAD then STORE data");
        check_mem(36, 32'h80F17F85, "LW");
        check_mem(37, 32'hFFFFFF85, "LB byte0 (neg)");
        check_mem(38, 32'h0000007F, "LB byte1 (pos)");
        check_mem(39, 32'hFFFFFFF1, "LB byte2 (neg)");
        check_mem(40, 32'hFFFFFF80, "LB byte3 (neg)");
        check_mem(41, 32'h00000085, "LBU byte0");
        check_mem(42, 32'h00000080, "LBU byte3");
        check_mem(43, 32'h00007F85, "LH low (pos)");
        check_mem(44, 32'hFFFF80F1, "LH high (neg)");
        check_mem(45, 32'h000080F1, "LHU high");
        check_mem(46, 32'h00007F85, "LHU low");
        check_mem(47, 32'h44332211, "SB x4 then LW");
        check_mem(48, 32'hBEEFBEEF, "SH x2 then LW");
        check_mem(49, 32'h80F17A85, "SB partial overwrite");
        check_mem(50, 32'h80F17A85, "LW negative offset");
        check_mem(51, 32'h000007FF, "BRANCH score A (tests 0-10)");
        check_mem(52, 32'h00000007, "BRANCH score B (tests 11-13)");
        check_mem(53, 32'h00000001, "back-to-back taken branches");
        check_mem(54, 32'h00000001, "forward into branch compare");
        check_mem(55, 32'h00000001, "branch after LOAD");
        check_mem(56, 32'h00000037, "LOOP sum 1..10 = 55");
        check_mem(57, 32'h00000378, "JAL link address");
        check_mem(58, 32'h00000390, "JALR link address");
        check_mem(59, 32'h000003A4, "JALR with imm");
        check_mem(60, 32'h0000000C, "CALL/RET double(6)=12");
        check_mem(61, 32'h00000000, "wrong-path flag (must be 0)");
        check_mem(62, 32'h00000000, "wrong-path store (must be 0)");
        check_mem(192, 32'h00000000, "RAM[0x300] untouched");
        $display("--- Kiem tra 32 thanh ghi ---");
        for (i = 0; i < 32; i = i + 1)
            check_reg(i, exp_reg[i]);

        $display("==============================================================");
        $display(" Tong so phep kiem tra dat : %0d", pass_cnt);
        $display(" Tong so phep kiem tra sai : %0d", fail_cnt);
        $display(" So lan phat hien X/Z      : %0d", x_cnt);
        $display(" So chu ky toi DONE_PC     : %0d (%0d lenh, CPI ~ %0d.%02d)", cycles_done, INSTR_COUNT,
                 (cycles_done*100/INSTR_COUNT)/100, (cycles_done*100/INSTR_COUNT)%100);
        if ((fail_cnt == 0) && (x_cnt == 0))
            $display(" *** ALL TESTS PASSED ***");
        else
            $display(" *** TEST FAILED ***");
        $display("==============================================================");
        $finish;                                   // Kết thúc mô phỏng
    end

endmodule                                          // Kết thúc testbench
