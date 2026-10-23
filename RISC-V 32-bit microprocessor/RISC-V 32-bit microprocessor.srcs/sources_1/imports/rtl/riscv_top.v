`timescale 1ns / 1ps                           // Đơn vị thời gian mô phỏng = 1ns, độ chính xác = 1ps
//==============================================================================
// Module : riscv_top  -  Top-level cho FPGA (mặc định cho board Basys 3, clk 100 MHz)
//==============================================================================
module riscv_top #(
    parameter PROGRAM         = 1,             // 1 = chương trình demo Fibonacci
    parameter DEBOUNCE_CYCLES = 1_000_000,     // Thời gian chống rung nút (10 ms tại 100 MHz)
    parameter DIV_SLOW        = 50_000_000,    // Chia tần cho chế độ chậm: 100 MHz / 50M = 2 Hz
    parameter DIV_MED         = 100,           // Chia tần cho chế độ vừa:   100 MHz / 100 = 1 MHz
    parameter REFRESH_BITS    = 16             // Độ rộng bộ đếm quét LED 7 đoạn
) (
    input  wire        clk,                    // Clock 100 MHz của board
    input  wire        btnC,                   // Nút giữa: reset
    input  wire        btnU,                   // Nút trên: chạy 1 bước
    input  wire [15:0] sw,                     // 16 công tắc gạt
    output wire [15:0] led,                    // 16 LED đơn
    output wire [6:0]  seg,                    // 7 đoạn LED
    output wire        dp,                     // Dấu chấm của LED 7 đoạn
    output wire [3:0]  an                      // Chọn chữ số LED 7 đoạn
);

    //---------------- Reset: đồng bộ nút btnC bằng 2 flip-flop ----------------
    reg rst_s0 = 1'b1;                         // Flip-flop đồng bộ 1 (khởi tạo = 1)
    reg rst_s1 = 1'b1;                         // Flip-flop đồng bộ 2
    reg rst_s2 = 1'b1;                         // Thêm 1 nhịp giữ reset để chờ sw ổn định sau khi nhả btnC
    always @(posedge clk) begin
        rst_s0 <= btnC;                        // Lấy mẫu nút reset
        rst_s1 <= rst_s0;                      // Qua tầng đồng bộ thứ hai
        rst_s2 <= rst_s1;                      // Trễ thêm 1 chu kỳ
    end
    // Kích hoạt reset ngay khi nhấn btnC (rst_s0) và giữ thêm 1 nhịp sau khi nhả (rst_s2)
    wire rst = rst_s0 | rst_s1 | rst_s2;       

    //---------------- Đồng bộ công tắc gạt ----------------
    reg [15:0] sw_s0 = 16'd0;                  // Tầng đồng bộ 1 cho 16 công tắc
    reg [15:0] sw_s1 = 16'd0;                  // Tầng đồng bộ 2 cho 16 công tắc
    always @(posedge clk) begin
        sw_s0 <= sw;                           // Lấy mẫu công tắc
        sw_s1 <= sw_s0;                        // Qua tầng đồng bộ thứ hai
    end
    wire [1:0] mode    = sw_s1[15:14];         // Chế độ tốc độ
    wire [4:0] reg_sel = sw_s1[4:0];           // Thanh ghi cần xem

    //---------------- Nút bước đơn ----------------
    wire step_pulse;                           // Xung 1 chu kỳ mỗi lần nhấn btnU
    button_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_step (
        .clk    (clk),
        .rst    (rst),
        .btn_in (btnU),
        .pulse  (step_pulse)
    );

    //---------------- Bộ chia tần tạo xung clock-enable ----------------
    reg [31:0] cnt_slow = 32'd0;               // Bộ đếm cho chế độ chậm
    reg [31:0] cnt_med  = 32'd0;               // Bộ đếm cho chế độ vừa
    wire tick_slow = (cnt_slow == DIV_SLOW - 1);
    wire tick_med  = (cnt_med  == DIV_MED  - 1);

    always @(posedge clk) begin
        if (rst) begin
            cnt_slow <= 32'd0;
            cnt_med  <= 32'd0;
        end else begin
            cnt_slow <= tick_slow ? 32'd0 : cnt_slow + 32'd1;
            cnt_med  <= tick_med  ? 32'd0 : cnt_med  + 32'd1;
        end
    end

    reg cpu_en;                                // Clock-enable cấp cho CPU
    always @(*) begin
        if (rst) begin
            cpu_en = 1'b0;                     // Không phát xung enable khi đang trong trạng thái reset
        end else begin
            case (mode)
                2'b00:   cpu_en = step_pulse;  // Chạy từng bước
                2'b01:   cpu_en = tick_slow;   // Chạy chậm
                2'b10:   cpu_en = tick_med;    // Chạy vừa
                default: cpu_en = 1'b1;        // Chạy tốc độ đầy đủ
            endcase
        end
    end

    //---------------- CPU RISC-V ----------------
    wire [31:0] dbg_reg_data;                  // Giá trị thanh ghi được chọn
    wire [31:0] dbg_pc;                        // PC hiện tại

    riscv_core #(.PROGRAM(PROGRAM)) u_core (
        .clk          (clk),
        .rst          (rst),
        .en           (cpu_en),
        .dbg_reg_addr (reg_sel),
        .dbg_reg_data (dbg_reg_data),
        .dbg_pc       (dbg_pc)
    );

    //---------------- Hiển thị ----------------
    assign led = dbg_pc[17:2];                 // LED đơn: chỉ số từ của PC (PC chia 4), 16 bit

    seg7_driver #(.REFRESH_BITS(REFRESH_BITS)) u_seg (
        .clk   (clk),
        .rst   (rst),
        .value (dbg_reg_data[15:0]),           // 16 bit thấp của thanh ghi đang chọn
        .seg   (seg),
        .an    (an),
        .dp    (dp)
    );

endmodule