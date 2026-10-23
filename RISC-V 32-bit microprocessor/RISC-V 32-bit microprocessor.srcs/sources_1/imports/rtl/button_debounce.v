`timescale 1ns / 1ps                       // Đơn vị thời gian mô phỏng = 1ns, độ chính xác = 1ps
//==============================================================================
// Module : button_debounce  (chống rung nút nhấn + tạo xung 1 chu kỳ)
// - Đồng bộ tín hiệu nút nhấn (bất đồng bộ) vào miền clock bằng 2 flip-flop.
// - Chỉ chấp nhận thay đổi khi tín hiệu ổn định đủ DEBOUNCE_CYCLES chu kỳ.
// - Mỗi lần nhấn (cạnh lên đã lọc rung) cho ra đúng 1 xung rộng 1 chu kỳ clock.
//==============================================================================
module button_debounce #(
    parameter DEBOUNCE_CYCLES = 1_000_000   // 1.000.000 chu kỳ x 10ns = 10ms tại 100 MHz
) (
    input  wire clk,                   // Xung clock hệ thống
    input  wire rst,                   // Reset đồng bộ, mức cao
    input  wire btn_in,                // Tín hiệu nút nhấn thô (có thể rung)
    output reg  pulse                  // Xung 1 chu kỳ khi nút được nhấn
);

    reg        sync0;                  // Flip-flop đồng bộ thứ nhất
    reg        sync1;                  // Flip-flop đồng bộ thứ hai
    reg        stable;                 // Trạng thái nút đã được xác nhận ổn định
    reg [31:0] cnt;                    // Bộ đếm thời gian ổn định

    always @(posedge clk) begin        // Chạy theo cạnh lên của clk
        if (rst) begin                 // Reset
            sync0  <= 1'b0;            //   xóa các flip-flop đồng bộ
            sync1  <= 1'b0;
            stable <= 1'b0;            //   coi như nút đang thả
            cnt    <= 32'd0;           //   xóa bộ đếm
            pulse  <= 1'b0;            //   không có xung
        end else begin
            sync0 <= btn_in;           // Lấy mẫu tín hiệu nút nhấn
            sync1 <= sync0;            // Qua tầng đồng bộ thứ hai (tránh metastability)
            pulse <= 1'b0;             // Mặc định không phát xung

            if (sync1 != stable) begin                     // Tín hiệu khác trạng thái đã xác nhận
                if (cnt == DEBOUNCE_CYCLES - 1) begin      //   đã ổn định đủ lâu
                    stable <= sync1;                       //     chấp nhận trạng thái mới
                    cnt    <= 32'd0;                       //     xóa bộ đếm
                    if (sync1) pulse <= 1'b1;              //     nếu là nhấn xuống thì phát 1 xung
                end else begin
                    cnt <= cnt + 32'd1;                    //   chưa đủ lâu: tiếp tục đếm
                end
            end else begin
                cnt <= 32'd0;                              // Tín hiệu trùng trạng thái cũ: xóa bộ đếm (loại nhiễu)
            end
        end
    end

endmodule                              // Kết thúc module button_debounce
