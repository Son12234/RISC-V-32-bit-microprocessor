`timescale 1ns / 1ps                       // Đơn vị thời gian mô phỏng = 1ns, độ chính xác = 1ps
//==============================================================================
// Module : seg7_driver  (điều khiển LED 7 đoạn 4 chữ số, quét ghép kênh)
// - Hiển thị giá trị 16 bit dưới dạng 4 chữ số hex (0-F).
// - Mỗi lúc chỉ sáng 1 chữ số, quét nhanh nên mắt thấy cả 4 chữ số cùng sáng.
// - Board Basys 3: đoạn LED và anode đều tích cực mức THẤP (0 = sáng).
//   seg[6:0] = {g,f,e,d,c,b,a};  an[0] là chữ số bên phải nhất.
//==============================================================================
module seg7_driver #(
    parameter REFRESH_BITS = 16        // Bộ đếm quét rộng 16 bit: ~1.5 kHz tại 100 MHz (mỗi chữ số ~380 Hz)
) (
    input  wire        clk,            // Xung clock hệ thống
    input  wire        rst,            // Reset đồng bộ, mức cao
    input  wire [15:0] value,          // Giá trị 16 bit cần hiển thị
    output reg  [6:0]  seg,            // 7 đoạn LED (tích cực thấp)
    output reg  [3:0]  an,             // Chọn chữ số (tích cực thấp)
    output wire        dp              // Dấu chấm thập phân
);

     reg [REFRESH_BITS-1:0] refresh_cnt;                        // Bộ đếm tự do dùng để quét


    always @(posedge clk) begin                                // Đếm theo cạnh lên của clk
        if (rst) refresh_cnt <= {REFRESH_BITS{1'b0}};          // Reset về 0
        else     refresh_cnt <= refresh_cnt + 1'b1;            // Mỗi xung clock tăng 1
    end

    wire [1:0] digit_sel = refresh_cnt[REFRESH_BITS-1:REFRESH_BITS-2];   // 2 bit cao chọn chữ số đang sáng

    reg [3:0] nibble;                                          // 4 bit (1 chữ số hex) của chữ số đang quét

    always @(*) begin                                          // Chọn chữ số và anode tương ứng
        case (digit_sel)
            2'd0:    begin nibble = value[3:0];   an = 4'b1110; end   // Chữ số phải nhất
            2'd1:    begin nibble = value[7:4];   an = 4'b1101; end   // Chữ số thứ 2
            2'd2:    begin nibble = value[11:8];  an = 4'b1011; end   // Chữ số thứ 3
            default: begin nibble = value[15:12]; an = 4'b0111; end   // Chữ số trái nhất
        endcase
    end

    always @(*) begin                                          // Giải mã hex -> 7 đoạn (0 = sáng)
        case (nibble)                                          //          gfedcba
            4'h0:    seg = 7'b1000000;                         // Hiển thị 0
            4'h1:    seg = 7'b1111001;                         // Hiển thị 1
            4'h2:    seg = 7'b0100100;                         // Hiển thị 2
            4'h3:    seg = 7'b0110000;                         // Hiển thị 3
            4'h4:    seg = 7'b0011001;                         // Hiển thị 4
            4'h5:    seg = 7'b0010010;                         // Hiển thị 5
            4'h6:    seg = 7'b0000010;                         // Hiển thị 6
            4'h7:    seg = 7'b1111000;                         // Hiển thị 7
            4'h8:    seg = 7'b0000000;                         // Hiển thị 8
            4'h9:    seg = 7'b0010000;                         // Hiển thị 9
            4'hA:    seg = 7'b0001000;                         // Hiển thị A
            4'hB:    seg = 7'b0000011;                         // Hiển thị b
            4'hC:    seg = 7'b1000110;                         // Hiển thị C
            4'hD:    seg = 7'b0100001;                         // Hiển thị d
            4'hE:    seg = 7'b0000110;                         // Hiển thị E
            default: seg = 7'b0001110;                         // Hiển thị F
        endcase
    end

    assign dp = 1'b1;                                          // Tắt dấu chấm thập phân (mức cao = tắt)

endmodule                                                      // Kết thúc module seg7_driver
