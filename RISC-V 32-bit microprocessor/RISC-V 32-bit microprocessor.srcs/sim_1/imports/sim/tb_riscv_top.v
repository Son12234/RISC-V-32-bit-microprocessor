`timescale 1ns / 1ps                        // Đơn vị thời gian mô phỏng = 1ns, độ chính xác = 1ps
//==============================================================================
// Testbench : tb_riscv_top  (kiểm tra phần giao tiếp với board: nút, công tắc, LED)
// Các thông số thời gian được thu nhỏ để mô phỏng nhanh (DEBOUNCE, DIV_SLOW, ...).
// Kiểm tra:
//   1. Sau reset ở chế độ chạy-từng-bước (sw[15:14] = 00) CPU đứng yên, PC = 0.
//   2. Nhấn btnU (có rung nút) -> đúng 1 xung enable -> PC tiến 1 chu kỳ.
//   3. Chạy tốc độ đầy đủ (11), dừng lại (00), rồi đọc LED 7 đoạn quét 4 chữ số
//      và so với giá trị thật trong register file (x5, x6, x10).
//   4. Chế độ chậm (01) và vừa (10) phát xung enable đúng tần suất.
// Kết quả cuối cùng: "*** ALL TESTS PASSED ***" hoặc "*** TEST FAILED ***".
//==============================================================================
module tb_riscv_top;

    localparam CLK_PERIOD = 10;                    // Chu kỳ clock 10ns (100 MHz)

    reg         clk  = 1'b0;                       // Clock hệ thống
    reg         btnC = 1'b1;                       // Nút reset (bắt đầu nhấn)
    reg         btnU = 1'b0;                       // Nút bước đơn
    reg  [15:0] sw   = 16'd0;                      // Công tắc gạt
    wire [15:0] led;                               // LED đơn
    wire [6:0]  seg;                               // 7 đoạn
    wire        dp;                                // Dấu chấm
    wire [3:0]  an;                                // Chọn chữ số

    integer pass_cnt = 0;                          // Số phép kiểm tra đạt
    integer fail_cnt = 0;                          // Số phép kiểm tra sai
    integer en_count = 0;                          // Đếm số xung enable cấp cho CPU
    integer x_cnt    = 0;                          // Đếm lần phát hiện X/Z ở đầu ra
    reg     monitor_en = 1'b0;                     // Cho phép giám sát sau khi reset xong

    riscv_top #(
        .PROGRAM         (1),                      // Chương trình demo Fibonacci
        .DEBOUNCE_CYCLES (4),                      // Chống rung 4 chu kỳ (thay vì 1.000.000)
        .DIV_SLOW        (40),                     // Chế độ chậm: 1 xung / 40 chu kỳ
        .DIV_MED         (8),                      // Chế độ vừa : 1 xung / 8 chu kỳ
        .REFRESH_BITS    (6)                       // Quét LED 7 đoạn nhanh: mỗi chữ số 16 chu kỳ
    ) dut (
        .clk (clk), .btnC (btnC), .btnU (btnU), .sw (sw),
        .led (led), .seg (seg), .dp (dp), .an (an)
    );

    always #(CLK_PERIOD/2) clk = ~clk;             // Tạo clock

    always @(posedge clk) begin
        if (dut.cpu_en === 1'b1) en_count = en_count + 1;   // Đếm xung enable
    end

    always @(negedge clk) begin                    // Giám sát X/Z ở các cổng ra (sau khi đã reset)
        if (monitor_en && !btnC) begin
            if ((^{led, seg, dp, an}) === 1'bx) begin
                x_cnt = x_cnt + 1;
                if (x_cnt <= 5) $display("[X-ERROR] t=%0t: cong ra co X/Z", $time);
            end
        end
    end

    // ---- Hàm giải mã 7 đoạn (tích cực thấp) -> {hợp lệ, hex} ----
    function [4:0] decode_seg;
        input [6:0] s;                             // Giá trị seg đọc được
        begin
            case (s)
                7'b1000000: decode_seg = {1'b1, 4'h0};
                7'b1111001: decode_seg = {1'b1, 4'h1};
                7'b0100100: decode_seg = {1'b1, 4'h2};
                7'b0110000: decode_seg = {1'b1, 4'h3};
                7'b0011001: decode_seg = {1'b1, 4'h4};
                7'b0010010: decode_seg = {1'b1, 4'h5};
                7'b0000010: decode_seg = {1'b1, 4'h6};
                7'b1111000: decode_seg = {1'b1, 4'h7};
                7'b0000000: decode_seg = {1'b1, 4'h8};
                7'b0010000: decode_seg = {1'b1, 4'h9};
                7'b0001000: decode_seg = {1'b1, 4'hA};
                7'b0000011: decode_seg = {1'b1, 4'hB};
                7'b1000110: decode_seg = {1'b1, 4'hC};
                7'b0100001: decode_seg = {1'b1, 4'hD};
                7'b0000110: decode_seg = {1'b1, 4'hE};
                7'b0001110: decode_seg = {1'b1, 4'hF};
                default:    decode_seg = 5'b0;     // Mã không hợp lệ
            endcase
        end
    endfunction

    // ---- Bộ thu: ghép 4 chữ số đang quét thành giá trị 16 bit ----
    reg [15:0] shown     = 16'd0;                  // Giá trị 16 bit ghép lại từ LED 7 đoạn
    reg [3:0]  seen      = 4'd0;                   // Bit i = 1 khi đã thấy chữ số i
    integer    bad_digit = 0;                      // Số lần gặp mã 7 đoạn không hợp lệ
    reg [4:0]  dec;                                // Kết quả giải mã tạm

    always @(negedge clk) begin
        if (monitor_en && !btnC) begin
            dec = decode_seg(seg);                     // Giải mã đoạn đang sáng
            case (an)                                  // Xác định chữ số đang được bật (mức thấp)
                4'b1110: begin seen[0] <= 1'b1; shown[3:0]   <= dec[3:0]; if (!dec[4]) bad_digit = bad_digit + 1; end
                4'b1101: begin seen[1] <= 1'b1; shown[7:4]   <= dec[3:0]; if (!dec[4]) bad_digit = bad_digit + 1; end
                4'b1011: begin seen[2] <= 1'b1; shown[11:8]  <= dec[3:0]; if (!dec[4]) bad_digit = bad_digit + 1; end
                4'b0111: begin seen[3] <= 1'b1; shown[15:12] <= dec[3:0]; if (!dec[4]) bad_digit = bad_digit + 1; end
                default: bad_digit = bad_digit + 1;    // Không đúng 1 chữ số sáng -> lỗi
            endcase
        end
    end

    // ---- Task kiểm tra chung ----
    task check;
        input        ok;                           // 1 = điều kiện đúng
        input [8*64-1:0] name;                     // Tên phép kiểm tra (tối đa 64 ký tự)
        begin
            if (ok) begin
                pass_cnt = pass_cnt + 1;
                $display("[PASS] %0s", name);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("[FAIL] %0s", name);
            end
        end
    endtask

    // ---- Task: chọn thanh ghi, chờ quét đủ 4 chữ số, so với register file ----
    task check_display;
        input integer r;                           // Số thứ tự thanh ghi
        reg [15:0] expected;                       // Giá trị thật 16 bit thấp
        begin
            sw = {2'b00, 9'd0, r[4:0]};            // Chế độ 00 (đứng yên) + chọn thanh ghi r
            repeat (8) @(posedge clk);             // Chờ công tắc qua mạch đồng bộ
            seen = 4'd0;                           // Xóa cờ "đã thấy chữ số"
            repeat (200) @(posedge clk);           // Chờ quét nhiều vòng (mỗi vòng 64 chu kỳ)
            expected = dut.u_core.u_regfile.regs[r];   // Giá trị thật trong register file
            check(seen === 4'hF,        "7-seg: du ca 4 chu so duoc quet");
            check(shown === expected,   "7-seg: gia tri hien thi = thanh ghi");
            $display("       x%0d = 0x%04h, 7-seg hien thi 0x%04h", r, expected, shown);
        end
    endtask

    integer c0;                                    // Biến đếm tạm
    reg [15:0] pc_before;                          // Lưu PC trước khi bước

    initial begin
`ifdef DUMP_VCD
        $dumpfile("tb_riscv_top.vcd");
        $dumpvars(0, tb_riscv_top);
`endif
        $display("==============================================================");
        $display(" TESTBENCH TOP-LEVEL (nut bam, cong tat, LED, LED 7 doan)");
        $display("==============================================================");

        // ---- 1. Reset ở chế độ bước đơn ----
        sw = 16'd0;                                // sw[15:14] = 00: chạy từng bước
        repeat (10) @(posedge clk);                // Giữ reset 10 chu kỳ
        btnC = 1'b0;                               // Thả nút reset
        repeat (10) @(posedge clk);                // Chờ ổn định
        en_count   = 0;                            // Xóa bộ đếm sau khi thoát reset hoàn toàn
        bad_digit  = 0;                            // Xóa lỗi 7 đoạn lúc chưa reset xong
        x_cnt      = 0;                            // Xóa lỗi X/Z lúc chưa reset xong
        monitor_en = 1'b1;                         // Bắt đầu giám sát chính thức

        check(led === 16'h0000, "Reset: PC = 0, CPU dung yen");
        check(en_count == 0,    "Che do 00: chua nhan nut -> khong co xung enable");

        // ---- 2. Nhấn btnU có rung nút ----
        pc_before = led;                           // Lưu PC (chia 4) trước khi bước
        en_count  = 0;                             // Xóa bộ đếm xung
        btnU = 1'b1; @(posedge clk);               // Rung: lên 1 chu kỳ
        btnU = 1'b0; @(posedge clk);               //       xuống 1 chu kỳ
        btnU = 1'b1; repeat (2) @(posedge clk);    //       lên 2 chu kỳ
        btnU = 1'b0; @(posedge clk);               //       xuống 1 chu kỳ
        btnU = 1'b1; repeat (30) @(posedge clk);   // Nhấn thật: giữ ổn định 30 chu kỳ
        btnU = 1'b0; repeat (30) @(posedge clk);   // Thả nút, chờ ổn định
        check(en_count == 1,             "Nhan btnU (co rung): dung 1 xung enable");
        check(led === (pc_before + 16'd1), "Sau 1 buoc: PC tang 4 (led +1)");

        // ---- 3. Chạy tốc độ đầy đủ rồi dừng, đọc LED 7 đoạn ----
        sw = {2'b11, 14'd0};                       // Chế độ 11: tốc độ đầy đủ
        repeat (600) @(posedge clk);               // Cho CPU chạy 600 chu kỳ
        check(dut.u_core.u_regfile.regs[5] > 32'd5, "Full speed: x5 (dem vong) da tang");
        check(led !== 16'h0000,                     "Full speed: PC dang chay (led != 0)");

        check_display(5);                          // x5  : bộ đếm vòng lặp
        check_display(6);                          // x6  : Fibonacci
        check_display(10);                         // x10 : giá trị đọc lại từ RAM
        check_display(0);                          // x0  : luôn bằng 0
        check(bad_digit == 0, "7-seg: khong co ma doan LED sai");

        // ---- 4. Chế độ chậm và vừa ----
        sw = {2'b01, 14'd0};                       // Chế độ 01: chậm (1 xung / 40 chu kỳ)
        repeat (8) @(posedge clk);                 // Chờ qua mạch đồng bộ
        en_count = 0;
        repeat (400) @(posedge clk);               // 400 chu kỳ -> kỳ vọng 10 xung
        c0 = en_count;
        check((c0 >= 9) && (c0 <= 11), "Che do cham: ~10 xung enable / 400 chu ky");
        $display("       so xung enable (che do cham) = %0d", c0);

        sw = {2'b10, 14'd0};                       // Chế độ 10: vừa (1 xung / 8 chu kỳ)
        repeat (8) @(posedge clk);
        en_count = 0;
        repeat (400) @(posedge clk);               // 400 chu kỳ -> kỳ vọng 50 xung
        c0 = en_count;
        check((c0 >= 49) && (c0 <= 51), "Che do vua: ~50 xung enable / 400 chu ky");
        $display("       so xung enable (che do vua) = %0d", c0);

        // ---- 5. Reset giữa chừng ----
        sw   = {2'b11, 14'd0};                     // Chạy đầy đủ
        repeat (50) @(posedge clk);
        btnC = 1'b1;                               // Nhấn reset
        sw   = 16'd0;                              // Chuyển về chế độ bước đơn trong lúc giữ reset
        repeat (10) @(posedge clk);                // Chờ reset và sw đi qua mạch đồng bộ
        btnC = 1'b0;                               // Thả reset
        repeat (8) @(posedge clk);                 // Chờ ổn định
        check(dut.u_core.pc <= 32'd8, "Reset giua chung: PC quay ve dau chuong trinh");
        check(x_cnt == 0,              "Khong co X/Z o cac cong ra");

        $display("==============================================================");
        $display(" Tong so phep kiem tra dat : %0d", pass_cnt);
        $display(" Tong so phep kiem tra sai : %0d", fail_cnt);
        if (fail_cnt == 0)
            $display(" *** ALL TESTS PASSED ***");
        else
            $display(" *** TEST FAILED ***");
        $display("==============================================================");
        $finish;                                   // Kết thúc mô phỏng
    end

endmodule                                          // Kết thúc testbench