`timescale 1ns / 1ps                       // Đơn vị thời gian mô phỏng = 1ns, độ chính xác = 1ps
//==============================================================================
// Module : branch_unit  (so sánh điều kiện cho lệnh rẽ nhánh, tầng EX)
// funct3 quyết định điều kiện:
//   000 BEQ  : a == b          001 BNE  : a != b
//   100 BLT  : a <  b (có dấu) 101 BGE  : a >= b (có dấu)
//   110 BLTU : a <  b (không dấu)  111 BGEU : a >= b (không dấu)
//==============================================================================
module branch_unit (
    input  wire [31:0] a,              // Giá trị rs1 (đã qua forwarding)
    input  wire [31:0] b,              // Giá trị rs2 (đã qua forwarding)
    input  wire [2:0]  funct3,         // Loại điều kiện rẽ nhánh
    output reg         cond            // 1 = điều kiện thỏa mãn
);

    always @(*) begin                  // Khối tổ hợp
        case (funct3)                  // Chọn phép so sánh theo funct3
            3'b000:  cond = (a == b);                       // BEQ : bằng nhau
            3'b001:  cond = (a != b);                       // BNE : khác nhau
            3'b100:  cond = ($signed(a) <  $signed(b));     // BLT : nhỏ hơn (có dấu)
            3'b101:  cond = ($signed(a) >= $signed(b));     // BGE : lớn hơn hoặc bằng (có dấu)
            3'b110:  cond = (a <  b);                       // BLTU: nhỏ hơn (không dấu)
            3'b111:  cond = (a >= b);                       // BGEU: lớn hơn hoặc bằng (không dấu)
            default: cond = 1'b0;                           // funct3 không hợp lệ -> không rẽ nhánh
        endcase                        // Kết thúc case
    end                                // Kết thúc khối always

endmodule                              // Kết thúc module branch_unit
