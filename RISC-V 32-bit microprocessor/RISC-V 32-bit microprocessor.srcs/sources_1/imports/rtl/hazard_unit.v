`timescale 1ns / 1ps                       // Đơn vị thời gian mô phỏng = 1ns, độ chính xác = 1ps
//==============================================================================
// Module : hazard_unit  (phát hiện hazard "load-use")
// Vấn đề : lệnh LOAD chỉ có dữ liệu sau tầng MEM. Nếu lệnh ngay sau nó cần đúng
//          thanh ghi đó thì forwarding cũng không kịp -> phải dừng pipeline 1 chu kỳ.
// Cách làm: khi stall = 1
//   - PC và thanh ghi IF/ID giữ nguyên (lệnh được fetch/giải mã lại ở chu kỳ sau)
//   - Thanh ghi ID/EX nhận một "bong bóng" (NOP) thay cho lệnh đang ở tầng ID
//==============================================================================
module hazard_unit (
    input  wire       ex_mem_read,     // Lệnh đang ở tầng EX là LOAD
    input  wire [4:0] ex_rd,           // Thanh ghi đích của lệnh ở tầng EX
    input  wire [4:0] id_rs1,          // Thanh ghi nguồn 1 của lệnh ở tầng ID
    input  wire [4:0] id_rs2,          // Thanh ghi nguồn 2 của lệnh ở tầng ID
    input  wire       id_uses_rs1,     // Lệnh ở tầng ID thật sự dùng rs1
    input  wire       id_uses_rs2,     // Lệnh ở tầng ID thật sự dùng rs2
    output wire       stall            // 1 = cần dừng pipeline 1 chu kỳ
);

    assign stall = ex_mem_read &&                       // Lệnh ở EX là LOAD
                   (ex_rd != 5'd0) &&                   // và ghi vào thanh ghi khác x0
                   ((id_uses_rs1 && (ex_rd == id_rs1)) ||   // và lệnh ở ID đọc đúng thanh ghi đó qua rs1
                    (id_uses_rs2 && (ex_rd == id_rs2)));    // hoặc qua rs2

endmodule                              // Kết thúc module hazard_unit
