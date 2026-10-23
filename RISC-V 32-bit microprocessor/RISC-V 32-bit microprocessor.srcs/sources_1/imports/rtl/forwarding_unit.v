`timescale 1ns / 1ps                       // Đơn vị thời gian mô phỏng = 1ns, độ chính xác = 1ps
//==============================================================================
// Module : forwarding_unit  (bộ chuyển tiếp dữ liệu - xử lý hazard RAW)
// Vấn đề : lệnh ở tầng EX cần rs1/rs2 nhưng giá trị đúng còn đang nằm ở
//          tầng MEM hoặc WB (chưa kịp ghi vào register file).
// Giải pháp: chuyển thẳng kết quả từ tầng sau về đầu vào ALU.
//   forward = 2'b10 : lấy từ thanh ghi EX/MEM (lệnh liền trước, ưu tiên cao nhất)
//   forward = 2'b01 : lấy từ MEM/WB          (lệnh cách 2 lệnh)
//   forward = 2'b00 : dùng giá trị đọc từ register file ở tầng ID
//==============================================================================
module forwarding_unit (
    input  wire [4:0] ex_rs1,          // Thanh ghi nguồn 1 của lệnh đang ở tầng EX
    input  wire [4:0] ex_rs2,          // Thanh ghi nguồn 2 của lệnh đang ở tầng EX
    input  wire [4:0] mem_rd,          // Thanh ghi đích của lệnh đang ở tầng MEM
    input  wire       mem_reg_write,   // Lệnh ở tầng MEM có ghi thanh ghi không
    input  wire [4:0] wb_rd,           // Thanh ghi đích của lệnh đang ở tầng WB
    input  wire       wb_reg_write,    // Lệnh ở tầng WB có ghi thanh ghi không
    output reg  [1:0] forward_a,       // Lựa chọn nguồn cho toán hạng rs1
    output reg  [1:0] forward_b        // Lựa chọn nguồn cho toán hạng rs2
);

    always @(*) begin                  // Khối tổ hợp
        // ---- Toán hạng A (rs1) ----
        forward_a = 2'b00;             // Mặc định: dùng giá trị từ register file
        if (mem_reg_write && (mem_rd != 5'd0) && (mem_rd == ex_rs1))
            forward_a = 2'b10;         // Lệnh liền trước ghi đúng rs1 -> lấy từ EX/MEM
        else if (wb_reg_write && (wb_rd != 5'd0) && (wb_rd == ex_rs1))
            forward_a = 2'b01;         // Lệnh cách 2 ghi đúng rs1 -> lấy từ MEM/WB

        // ---- Toán hạng B (rs2) ----
        forward_b = 2'b00;             // Mặc định: dùng giá trị từ register file
        if (mem_reg_write && (mem_rd != 5'd0) && (mem_rd == ex_rs2))
            forward_b = 2'b10;         // Lệnh liền trước ghi đúng rs2 -> lấy từ EX/MEM
        else if (wb_reg_write && (wb_rd != 5'd0) && (wb_rd == ex_rs2))
            forward_b = 2'b01;         // Lệnh cách 2 ghi đúng rs2 -> lấy từ MEM/WB
    end                                // (điều kiện rd != 0 để không bao giờ chuyển tiếp "giá trị" của x0)

endmodule                              // Kết thúc module forwarding_unit
