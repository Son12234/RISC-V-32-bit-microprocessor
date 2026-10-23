`timescale 1ns / 1ps                       // Đơn vị thời gian mô phỏng = 1ns, độ chính xác = 1ps
//==============================================================================
// Module : control_unit  (giải mã lệnh, sinh tín hiệu điều khiển - tầng ID)
// Đầu vào: opcode, funct3, funct7[5] của lệnh.
// Đầu ra : các tín hiệu điều khiển đi theo lệnh qua các tầng EX -> MEM -> WB.
// Lệnh lạ / FENCE / ECALL / EBREAK được coi như NOP (mọi tín hiệu = 0).
//==============================================================================
module control_unit (
    input  wire [6:0] opcode,          // 7 bit thấp của lệnh, cho biết loại lệnh
    input  wire [2:0] funct3,          // Trường funct3: phân biệt các lệnh cùng loại
    input  wire       funct7_5,        // Bit 30 của lệnh: phân biệt ADD/SUB và SRL/SRA
    output reg        reg_write,       // 1 = lệnh ghi kết quả vào thanh ghi rd
    output reg        mem_read,        // 1 = lệnh LOAD (đọc bộ nhớ dữ liệu)
    output reg        mem_write,       // 1 = lệnh STORE (ghi bộ nhớ dữ liệu)
    output reg        mem_to_reg,      // 1 = dữ liệu ghi về rd lấy từ bộ nhớ, 0 = lấy từ ALU
    output reg [1:0]  alu_src_a,       // Chọn toán hạng A của ALU: 00 = rs1, 01 = PC, 10 = số 0
    output reg        alu_src_b,       // Chọn toán hạng B của ALU: 0 = rs2, 1 = số tức thời (imm)
    output reg [3:0]  alu_op,          // Mã phép toán gửi cho ALU
    output reg        branch,          // 1 = lệnh rẽ nhánh có điều kiện (BEQ, BNE, BLT, ...)
    output reg        jal,             // 1 = lệnh JAL (nhảy tuyệt đối theo PC + imm)
    output reg        jalr,            // 1 = lệnh JALR (nhảy theo rs1 + imm)
    output reg        uses_rs1,        // 1 = lệnh thực sự đọc rs1 (dùng để phát hiện hazard)
    output reg        uses_rs2         // 1 = lệnh thực sự đọc rs2 (dùng để phát hiện hazard)
);

    // ---- Mã opcode của các nhóm lệnh RV32I (theo đặc tả RISC-V) ----
    localparam [6:0] OP_LUI    = 7'b0110111;   // LUI    : nạp số 20 bit vào phần cao của rd
    localparam [6:0] OP_AUIPC  = 7'b0010111;   // AUIPC  : rd = PC + (imm20 << 12)
    localparam [6:0] OP_JAL    = 7'b1101111;   // JAL    : nhảy và lưu địa chỉ quay về
    localparam [6:0] OP_JALR   = 7'b1100111;   // JALR   : nhảy theo thanh ghi và lưu địa chỉ quay về
    localparam [6:0] OP_BRANCH = 7'b1100011;   // BEQ, BNE, BLT, BGE, BLTU, BGEU
    localparam [6:0] OP_LOAD   = 7'b0000011;   // LB, LH, LW, LBU, LHU
    localparam [6:0] OP_STORE  = 7'b0100011;   // SB, SH, SW
    localparam [6:0] OP_IMM    = 7'b0010011;   // ADDI, SLTI, XORI, ORI, ANDI, SLLI, SRLI, SRAI
    localparam [6:0] OP_REG    = 7'b0110011;   // ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND

    always @(*) begin                  // Khối tổ hợp: giải mã ngay khi lệnh thay đổi
        // Giá trị mặc định = NOP: tránh sinh latch và tránh tín hiệu X
        reg_write  = 1'b0;             // Mặc định không ghi thanh ghi
        mem_read   = 1'b0;             // Mặc định không đọc bộ nhớ
        mem_write  = 1'b0;             // Mặc định không ghi bộ nhớ
        mem_to_reg = 1'b0;             // Mặc định kết quả lấy từ ALU
        alu_src_a  = 2'b00;            // Mặc định toán hạng A = rs1
        alu_src_b  = 1'b0;             // Mặc định toán hạng B = rs2
        alu_op     = 4'b0000;          // Mặc định ALU làm phép cộng
        branch     = 1'b0;             // Mặc định không phải lệnh rẽ nhánh
        jal        = 1'b0;             // Mặc định không phải JAL
        jalr       = 1'b0;             // Mặc định không phải JALR
        uses_rs1   = 1'b0;             // Mặc định không đọc rs1
        uses_rs2   = 1'b0;             // Mặc định không đọc rs2

        case (opcode)                  // Chọn tín hiệu điều khiển theo opcode
            OP_LUI: begin              // LUI: rd = imm20 << 12
                reg_write = 1'b1;      //   có ghi rd
                alu_src_a = 2'b10;     //   A = 0
                alu_src_b = 1'b1;      //   B = imm (đã dịch 12 bit trong imm_gen)
            end                        //   alu_op giữ mặc định = ADD  => 0 + imm
            OP_AUIPC: begin            // AUIPC: rd = PC + (imm20 << 12)
                reg_write = 1'b1;      //   có ghi rd
                alu_src_a = 2'b01;     //   A = PC
                alu_src_b = 1'b1;      //   B = imm
            end                        //   alu_op = ADD
            OP_JAL: begin              // JAL: rd = PC + 4, PC = PC + imm
                reg_write = 1'b1;      //   ghi địa chỉ quay về vào rd (PC+4 được chọn ở tầng EX)
                jal       = 1'b1;      //   báo cho tầng EX biết đây là JAL
            end
            OP_JALR: begin             // JALR: rd = PC + 4, PC = (rs1 + imm) & ~1
                reg_write = 1'b1;      //   ghi địa chỉ quay về vào rd
                jalr      = 1'b1;      //   báo cho tầng EX biết đây là JALR
                uses_rs1  = 1'b1;      //   có đọc rs1
            end
            OP_BRANCH: begin           // BEQ/BNE/BLT/BGE/BLTU/BGEU
                branch    = 1'b1;      //   báo cho tầng EX so sánh rs1 với rs2
                uses_rs1  = 1'b1;      //   có đọc rs1
                uses_rs2  = 1'b1;      //   có đọc rs2
            end
            OP_LOAD: begin             // LB/LH/LW/LBU/LHU: rd = Mem[rs1 + imm]
                reg_write  = 1'b1;     //   ghi dữ liệu đọc được vào rd
                mem_read   = 1'b1;     //   đây là lệnh đọc bộ nhớ (hazard_unit cần biết)
                mem_to_reg = 1'b1;     //   dữ liệu ghi về lấy từ bộ nhớ
                alu_src_b  = 1'b1;     //   B = imm: ALU tính địa chỉ = rs1 + imm
                uses_rs1   = 1'b1;     //   có đọc rs1 (thanh ghi cơ sở)
            end
            OP_STORE: begin            // SB/SH/SW: Mem[rs1 + imm] = rs2
                mem_write = 1'b1;      //   đây là lệnh ghi bộ nhớ
                alu_src_b = 1'b1;      //   B = imm: ALU tính địa chỉ = rs1 + imm
                uses_rs1  = 1'b1;      //   có đọc rs1 (thanh ghi cơ sở)
                uses_rs2  = 1'b1;      //   có đọc rs2 (dữ liệu cần ghi)
            end
            OP_IMM: begin              // Lệnh ALU với số tức thời
                reg_write = 1'b1;      //   ghi kết quả vào rd
                alu_src_b = 1'b1;      //   B = imm
                uses_rs1  = 1'b1;      //   có đọc rs1
                // Chỉ các lệnh dịch phải (funct3 = 101) mới dùng bit 30 để phân biệt SRLI/SRAI.
                // Với ADDI bit 30 là một phần của imm nên KHÔNG được coi là SUB.
                alu_op    = (funct3 == 3'b101) ? {funct7_5, funct3} : {1'b0, funct3};
            end
            OP_REG: begin              // Lệnh ALU giữa hai thanh ghi
                reg_write = 1'b1;      //   ghi kết quả vào rd
                uses_rs1  = 1'b1;      //   có đọc rs1
                uses_rs2  = 1'b1;      //   có đọc rs2
                alu_op    = {funct7_5, funct3};   // bit 30 phân biệt ADD/SUB, SRL/SRA
            end
            default: begin             // Opcode khác (FENCE, ECALL, EBREAK, lệnh lạ)
                // Giữ nguyên giá trị mặc định = NOP
            end
        endcase                        // Kết thúc case
    end                                // Kết thúc khối always

endmodule                              // Kết thúc module control_unit
