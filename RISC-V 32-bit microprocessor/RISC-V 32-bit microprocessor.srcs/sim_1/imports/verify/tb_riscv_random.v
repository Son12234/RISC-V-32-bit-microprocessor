`timescale 1ns / 1ps                       // Đơn vị thời gian mô phỏng = 1ns, độ chính xác = 1ps
//==============================================================================
// Testbench : tb_riscv_random  (kiểm thử ngẫu nhiên - dùng kèm verify/random_test.py)
// Ý tưởng   : script Python sinh chương trình RV32I ngẫu nhiên -> ghi ra file prog.hex.
//             Testbench này nạp prog.hex vào ROM lệnh, cho CPU chạy một số chu kỳ cố định
//             rồi ghi 32 thanh ghi + vùng RAM dữ liệu ra file dump.txt.
//             Script Python chạy cùng chương trình trên mô hình tham chiếu và so sánh.
// Tham số dòng lệnh (plusargs):  +prog=<file hex>  +dump=<file kết quả>  +cycles=<số chu kỳ>
//                               +enmode=1 -> clock-enable (en) bật/tắt NGẪU NHIÊN mỗi chu kỳ
//                                            (giống chế độ chạy chậm / từng bước trên board)
//==============================================================================
module tb_riscv_random;

    reg         clk = 1'b0;                        // Tín hiệu clock
    reg         rst = 1'b1;                        // Reset (bắt đầu ở mức 1)
    reg         en  = 1'b1;                        // Clock-enable của CPU (mặc định luôn bật)
    integer     enmode = 0;                        // 1 = en thay đổi ngẫu nhiên
    wire [31:0] dbg_reg_data;                      // Cổng debug thanh ghi (không dùng ở đây)
    wire [31:0] dbg_pc;                            // PC hiện tại

    riscv_core #(.PROGRAM(0)) dut (                // CPU cần kiểm tra
        .clk(clk), .rst(rst), .en(en),
        .dbg_reg_addr(5'd0), .dbg_reg_data(dbg_reg_data), .dbg_pc(dbg_pc)
    );

    always #5 clk = ~clk;                          // Clock 100 MHz (chu kỳ 10ns)

    reg [8*256-1:0] prog_file;                     // Tên file chương trình
    reg [8*256-1:0] dump_file;                     // Tên file kết quả
    integer         cycles;                        // Số chu kỳ cần chạy
    integer         fd;                            // Con trỏ file
    integer         i;                             // Biến chạy
    integer         x_cnt = 0;                     // Đếm số lần phát hiện X/Z

    always @(negedge clk) begin                    // Tạo clock-enable ngẫu nhiên (đổi ở cạnh xuống, tránh đua tín hiệu)
        if (enmode != 0) en = ($random & 3) != 0;  // ~75% chu kỳ bật, 25% chu kỳ đóng băng
        else             en = 1'b1;                // Chế độ thường: luôn bật
    end

    always @(negedge clk) begin                    // Giám sát X/Z trong pipeline
        if (!rst && ((^{dut.pc, dut.ifid_instr, dut.ex_alu_result, dut.exmem_alu_result,
                        dut.memwb_alu_result, dut.memwb_rdata, dut.wb_data}) === 1'bx))
            x_cnt = x_cnt + 1;
    end

    initial begin
        if (!$value$plusargs("prog=%s", prog_file))  prog_file = "prog.hex";
        if (!$value$plusargs("dump=%s", dump_file))  dump_file = "dump.txt";
        if (!$value$plusargs("cycles=%d", cycles))   cycles    = 2000;
        if (!$value$plusargs("enmode=%d", enmode))   enmode    = 0;
        #1;                                        // Đợi khối initial của instr_mem chạy xong (điền NOP)
        $readmemh(prog_file, dut.u_imem.mem);      // Ghi đè chương trình ngẫu nhiên vào ROM lệnh
        repeat (4) @(posedge clk);                 // Giữ reset 4 chu kỳ
        #1 rst = 1'b0;                             // Thả reset
        repeat (cycles) @(posedge clk);            // Chạy số chu kỳ yêu cầu
        #1;
        fd = $fopen(dump_file, "w");               // Ghi kết quả ra file
        for (i = 0; i < 32; i = i + 1)
            $fdisplay(fd, "x%0d %08x", i, (i == 0) ? 32'd0 : dut.u_regfile.regs[i]);
        for (i = 0; i < 256; i = i + 1)
            $fdisplay(fd, "m%0d %08x", i, {dut.u_dmem.mem3[i], dut.u_dmem.mem2[i],
                                           dut.u_dmem.mem1[i], dut.u_dmem.mem0[i]});
        $fdisplay(fd, "xz %0d", x_cnt);
        $fclose(fd);
        $finish;
    end

endmodule                                          // Kết thúc testbench
