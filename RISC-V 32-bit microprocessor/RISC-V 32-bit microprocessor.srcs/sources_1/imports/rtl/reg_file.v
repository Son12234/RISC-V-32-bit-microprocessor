`timescale 1ns / 1ps                       // Đơn vị thời gian mô phỏng = 1ns, độ chính xác = 1ps
//==============================================================================
// Module : reg_file  (tập 32 thanh ghi x0..x31, mỗi thanh ghi 32 bit)
// - Đọc bất đồng bộ (tổ hợp) 2 cổng cho tầng ID + 1 cổng debug cho FPGA/testbench.
// - Ghi đồng bộ theo cạnh lên của xung clock (tầng WB).
// - x0 luôn bằng 0, ghi vào x0 bị bỏ qua.
// - Có "write-through bypass": nếu tầng WB đang ghi đúng thanh ghi mà tầng ID đang
//   đọc trong cùng chu kỳ, dữ liệu mới được chuyển thẳng sang cổng đọc
//   (giải quyết hazard khoảng cách 3 lệnh).
//==============================================================================
module reg_file (
    input  wire        clk,            // Xung clock
    input  wire        we,             // Cho phép ghi (đã gồm reg_write và clock-enable)
    input  wire [4:0]  waddr,          // Số thứ tự thanh ghi cần ghi
    input  wire [31:0] wdata,          // Dữ liệu cần ghi
    input  wire [4:0]  raddr1,         // Số thứ tự thanh ghi đọc cổng 1 (rs1)
    input  wire [4:0]  raddr2,         // Số thứ tự thanh ghi đọc cổng 2 (rs2)
    output wire [31:0] rdata1,         // Dữ liệu đọc cổng 1
    output wire [31:0] rdata2,         // Dữ liệu đọc cổng 2
    input  wire [4:0]  dbg_addr,       // Cổng debug: chọn thanh ghi muốn xem
    output wire [31:0] dbg_data        // Cổng debug: giá trị thanh ghi được chọn
);

    (* ram_style = "distributed" *)    // Gợi ý cho Vivado: dùng LUT-RAM (đọc bất đồng bộ)
    reg [31:0] regs [0:31];            // Mảng 32 thanh ghi, mỗi thanh ghi rộng 32 bit

    integer i;                         // Biến chạy cho vòng lặp khởi tạo
    initial begin                      // Khối khởi tạo (mô phỏng và cấu hình ban đầu FPGA)
        for (i = 0; i < 32; i = i + 1) // Duyệt qua cả 32 thanh ghi
            regs[i] = 32'd0;           // Xóa về 0 để không có giá trị X khi mô phỏng
    end

    always @(posedge clk) begin        // Ghi đồng bộ theo cạnh lên của clk
        if (we && (waddr != 5'd0))     // Chỉ ghi khi được phép và không phải x0
            regs[waddr] <= wdata;      // Ghi dữ liệu vào thanh ghi đích
    end

    // Cổng đọc 1: x0 -> 0; nếu đang ghi đúng thanh ghi này thì lấy dữ liệu mới; còn lại đọc mảng
    assign rdata1 = (raddr1 == 5'd0)                  ? 32'd0 :
                    (we && (waddr == raddr1))         ? wdata :
                                                        regs[raddr1];
    // Cổng đọc 2: tương tự cổng 1 nhưng cho rs2
    assign rdata2 = (raddr2 == 5'd0)                  ? 32'd0 :
                    (we && (waddr == raddr2))         ? wdata :
                                                        regs[raddr2];
    // Cổng debug: đọc thẳng giá trị đang lưu trong thanh ghi
    assign dbg_data = (dbg_addr == 5'd0) ? 32'd0 : regs[dbg_addr];

endmodule                              // Kết thúc module reg_file
