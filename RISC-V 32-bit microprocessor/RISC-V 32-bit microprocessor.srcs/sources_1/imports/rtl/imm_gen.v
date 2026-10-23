`timescale 1ns / 1ps                       // Đơn vị thời gian mô phỏng = 1ns, độ chính xác = 1ps
//==============================================================================
// Module : imm_gen  (bộ sinh số tức thời - immediate generator)
// Vai trò: RISC-V có 5 kiểu lệnh (I, S, B, U, J), mỗi kiểu xếp các bit imm ở
//          vị trí khác nhau. Module này gom lại và mở rộng dấu thành 32 bit.
//==============================================================================
module imm_gen (
    input  wire [31:0] instr,          // Toàn bộ lệnh 32 bit
    output reg  [31:0] imm             // Số tức thời đã mở rộng dấu thành 32 bit
);

    wire [6:0] opcode = instr[6:0];    // Lấy opcode để biết lệnh thuộc kiểu nào

    always @(*) begin                  // Khối tổ hợp
        case (opcode)                  // Chọn cách ghép imm theo opcode
            7'b0010011,                // Kiểu I: lệnh ALU với số tức thời
            7'b0000011,                // Kiểu I: lệnh LOAD
            7'b1100111:                // Kiểu I: lệnh JALR
                imm = {{20{instr[31]}}, instr[31:20]};                                  // imm[11:0] = instr[31:20], mở rộng dấu bằng bit 31
            7'b0100011:                // Kiểu S: lệnh STORE
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};                     // imm[11:5] = instr[31:25], imm[4:0] = instr[11:7]
            7'b1100011:                // Kiểu B: lệnh rẽ nhánh
                imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0}; // imm[12|10:5|4:1|11], bit 0 luôn = 0
            7'b0110111,                // Kiểu U: lệnh LUI
            7'b0010111:                // Kiểu U: lệnh AUIPC
                imm = {instr[31:12], 12'b0};                                            // imm[31:12] = instr[31:12], 12 bit thấp = 0
            7'b1101111:                // Kiểu J: lệnh JAL
                imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0}; // imm[20|10:1|11|19:12], bit 0 luôn = 0
            default:                   // Opcode khác: không dùng imm
                imm = 32'd0;           // Trả về 0 để không có tín hiệu X
        endcase                        // Kết thúc case
    end                                // Kết thúc khối always

endmodule                              // Kết thúc module imm_gen
