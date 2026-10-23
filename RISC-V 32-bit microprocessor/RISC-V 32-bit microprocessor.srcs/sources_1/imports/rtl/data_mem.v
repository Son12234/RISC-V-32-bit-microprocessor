`timescale 1ns / 1ps                       // Đơn vị thời gian mô phỏng = 1ns, độ chính xác = 1ps
//==============================================================================
// Module : data_mem  (bộ nhớ dữ liệu, tầng MEM)
// - Kích thước mặc định 2^ADDR_BITS từ (8 -> 256 từ = 1 KiB).
// - Tổ chức thành 4 "làn byte" (mem0..mem3) để ghi được từng byte / nửa từ / cả từ.
// - Đọc bất đồng bộ (tổ hợp); ghi đồng bộ theo cạnh lên của clk.
// - Hỗ trợ LB, LH, LW, LBU, LHU và SB, SH, SW. Địa chỉ phải được căn hàng
//   (LH/SH: chẵn, LW/SW: chia hết cho 4). Truy cập sai hàng không được hỗ trợ.
// - Địa chỉ vượt quá kích thước sẽ bị "quấn vòng" (aliasing).
//==============================================================================
module data_mem #(
    parameter ADDR_BITS = 8            // Số bit chỉ số từ: 2^8 = 256 từ
) (
    input  wire        clk,            // Xung clock
    input  wire        we,             // 1 = ghi (lệnh STORE ở tầng MEM, đã gồm clock-enable)
    input  wire [2:0]  funct3,         // Kích thước/kiểu truy cập (lấy từ funct3 của lệnh)
    input  wire [31:0] addr,           // Địa chỉ byte (do ALU tính)
    input  wire [31:0] wdata,          // Dữ liệu cần ghi (giá trị rs2)
    output reg  [31:0] rdata           // Dữ liệu đọc ra (đã dịch và mở rộng dấu / không dấu)
);

    localparam DEPTH = 1 << ADDR_BITS; // Số từ 32 bit trong bộ nhớ

    (* ram_style = "distributed" *) reg [7:0] mem0 [0:DEPTH-1];   // Làn byte 0 (bit 7:0)
    (* ram_style = "distributed" *) reg [7:0] mem1 [0:DEPTH-1];   // Làn byte 1 (bit 15:8)
    (* ram_style = "distributed" *) reg [7:0] mem2 [0:DEPTH-1];   // Làn byte 2 (bit 23:16)
    (* ram_style = "distributed" *) reg [7:0] mem3 [0:DEPTH-1];   // Làn byte 3 (bit 31:24)

    integer i;                         // Biến chạy cho vòng lặp khởi tạo
    initial begin                      // Khởi tạo toàn bộ bộ nhớ = 0 (tránh giá trị X khi mô phỏng)
        for (i = 0; i < DEPTH; i = i + 1) begin
            mem0[i] = 8'd0;            // Xóa làn 0
            mem1[i] = 8'd0;            // Xóa làn 1
            mem2[i] = 8'd0;            // Xóa làn 2
            mem3[i] = 8'd0;            // Xóa làn 3
        end
    end

    wire [ADDR_BITS-1:0] widx = addr[ADDR_BITS+1:2];   // Chỉ số từ = địa chỉ byte chia 4
    wire [1:0]           boff = addr[1:0];             // Vị trí byte trong từ (0..3)

    // ------------------------- GHI (STORE) -------------------------
    reg [3:0]  be;                     // Byte-enable: bit i = 1 thì làn byte i được ghi
    reg [31:0] wdata_rep;              // Dữ liệu đã nhân bản để mỗi làn nhận đúng byte của nó

    always @(*) begin                  // Khối tổ hợp tính byte-enable và dữ liệu ghi
        case (funct3[1:0])             // funct3[1:0]: 00 = byte, 01 = nửa từ, 10 = từ
            2'b00: begin               // SB: ghi 1 byte
                be        = 4'b0001 << boff;          // Bật đúng làn byte theo địa chỉ
                wdata_rep = {4{wdata[7:0]}};          // Nhân bản byte thấp ra cả 4 làn
            end
            2'b01: begin               // SH: ghi 2 byte
                be        = boff[1] ? 4'b1100 : 4'b0011;  // Nửa trên hoặc nửa dưới của từ
                wdata_rep = {2{wdata[15:0]}};         // Nhân bản nửa từ thấp ra 2 nửa
            end
            default: begin             // SW: ghi cả từ 4 byte
                be        = 4'b1111;                  // Bật cả 4 làn
                wdata_rep = wdata;                    // Ghi nguyên dữ liệu
            end
        endcase                        // Kết thúc case
    end

    always @(posedge clk) begin        // Ghi đồng bộ theo cạnh lên của clk
        if (we) begin                  // Chỉ ghi khi lệnh STORE đang ở tầng MEM
            if (be[0]) mem0[widx] <= wdata_rep[7:0];    // Ghi làn 0 nếu được bật
            if (be[1]) mem1[widx] <= wdata_rep[15:8];   // Ghi làn 1 nếu được bật
            if (be[2]) mem2[widx] <= wdata_rep[23:16];  // Ghi làn 2 nếu được bật
            if (be[3]) mem3[widx] <= wdata_rep[31:24];  // Ghi làn 3 nếu được bật
        end
    end

    // ------------------------- ĐỌC (LOAD) -------------------------
    wire [31:0] rword   = {mem3[widx], mem2[widx], mem1[widx], mem0[widx]};  // Đọc nguyên từ 32 bit
    wire [31:0] shifted = rword >> {boff, 3'b000};     // Dịch phải (boff*8) bit để byte cần đọc về bit thấp nhất

    always @(*) begin                  // Khối tổ hợp: mở rộng dấu / không dấu theo funct3
        case (funct3)                  // funct3 cho biết loại LOAD
            3'b000:  rdata = {{24{shifted[7]}},  shifted[7:0]};   // LB : mở rộng dấu từ byte
            3'b001:  rdata = {{16{shifted[15]}}, shifted[15:0]};  // LH : mở rộng dấu từ nửa từ
            3'b010:  rdata = shifted;                             // LW : lấy nguyên từ
            3'b100:  rdata = {24'd0, shifted[7:0]};               // LBU: mở rộng không dấu từ byte
            3'b101:  rdata = {16'd0, shifted[15:0]};              // LHU: mở rộng không dấu từ nửa từ
            default: rdata = shifted;                             // Giá trị khác: trả nguyên từ
        endcase                        // Kết thúc case
    end

endmodule                              // Kết thúc module data_mem
