`timescale 1ns / 1ps                       // Đơn vị thời gian mô phỏng = 1ns, độ chính xác = 1ps
//==============================================================================
// Module : alu  (Arithmetic Logic Unit - khối số học / logic)
// Vai trò: thực hiện các phép tính của RV32I trong tầng EX.
// Mã alu_op (4 bit) được ghép từ {funct7[5], funct3} nên bảng tra rất gọn:
//   0000 ADD | 1000 SUB | 0001 SLL | 0010 SLT | 0011 SLTU
//   0100 XOR | 0101 SRL | 1101 SRA | 0110 OR  | 0111 AND
//==============================================================================
module alu (
    input  wire [31:0] a,              // Toán hạng A (32 bit)
    input  wire [31:0] b,              // Toán hạng B (32 bit)
    input  wire [3:0]  alu_op,         // Mã phép toán do control_unit sinh ra
    output reg  [31:0] result          // Kết quả của phép toán
);

    wire [4:0] shamt = b[4:0];         // Số bit cần dịch: chỉ lấy 5 bit thấp của B (giá trị 0..31)

    always @(*) begin                  // Khối tổ hợp: kết quả đổi ngay khi đầu vào đổi
        case (alu_op)                  // Chọn phép toán theo mã alu_op
            4'b0000: result = a + b;                                       // ADD, ADDI, địa chỉ LOAD/STORE, AUIPC, LUI
            4'b1000: result = a - b;                                       // SUB
            4'b0001: result = a << shamt;                                  // SLL, SLLI: dịch trái logic
            4'b0010: result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;   // SLT, SLTI: so sánh có dấu, đúng thì = 1
            4'b0011: result = (a < b) ? 32'd1 : 32'd0;                     // SLTU, SLTIU: so sánh không dấu
            4'b0100: result = a ^ b;                                       // XOR, XORI
            4'b0101: result = a >> shamt;                                  // SRL, SRLI: dịch phải logic (chèn bit 0)
            4'b1101: result = $signed(a) >>> shamt;                        // SRA, SRAI: dịch phải số học (giữ bit dấu)
            4'b0110: result = a | b;                                       // OR, ORI
            4'b0111: result = a & b;                                       // AND, ANDI
            default: result = 32'd0;                                       // Mã không hợp lệ -> trả về 0 (tránh tín hiệu X)
        endcase                        // Kết thúc case
    end                                // Kết thúc khối always

endmodule                              // Kết thúc module alu
