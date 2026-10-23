`timescale 1ns / 1ps                       // Đơn vị thời gian mô phỏng = 1ns, độ chính xác = 1ps
//==============================================================================
// Module : riscv_core  -  CPU RISC-V RV32I, pipeline 5 tầng
//
//   IF  : Instruction Fetch   - lấy lệnh từ bộ nhớ lệnh tại địa chỉ PC
//   ID  : Instruction Decode  - giải mã lệnh, đọc thanh ghi, sinh số tức thời
//   EX  : Execute             - ALU, so sánh nhánh, tính địa chỉ nhảy, forwarding
//   MEM : Memory access       - đọc/ghi bộ nhớ dữ liệu (LOAD/STORE)
//   WB  : Write Back          - ghi kết quả về register file
//
// Xử lý hazard:
//   * RAW giữa các lệnh ALU : forwarding EX/MEM -> EX và MEM/WB -> EX
//   * RAW kiểu "load-use"   : dừng (stall) 1 chu kỳ + forwarding từ MEM/WB
//   * Rẽ nhánh / nhảy       : quyết định ở tầng EX; nếu rẽ thì xóa (flush) 2 lệnh
//                             đã nạp nhầm (phạt 2 chu kỳ), dự đoán "không rẽ"
//   * Ghi/đọc cùng thanh ghi trong cùng chu kỳ (WB -> ID): bypass trong reg_file
//
// Tín hiệu en (clock-enable): en = 0 thì toàn bộ CPU đứng yên (dùng để chạy
// chậm / chạy từng bước trên board). Khi mô phỏng chỉ cần nối en = 1.
//==============================================================================
module riscv_core #(
    parameter PROGRAM = 0              // 0 = chương trình kiểm thử ISA, 1 = chương trình demo Fibonacci
) (
    input  wire        clk,            // Xung clock hệ thống
    input  wire        rst,            // Reset đồng bộ, mức cao
    input  wire        en,             // Clock-enable: 1 = pipeline chạy, 0 = đóng băng
    input  wire [4:0]  dbg_reg_addr,   // Debug: số thứ tự thanh ghi muốn xem
    output wire [31:0] dbg_reg_data,   // Debug: giá trị thanh ghi được chọn
    output wire [31:0] dbg_pc          // Debug: giá trị PC hiện tại
);

    localparam [31:0] NOP = 32'h0000_0013;   // Lệnh NOP = addi x0, x0, 0 (không làm gì cả)

    //==========================================================================
    // KHAI BÁO TẤT CẢ TÍN HIỆU (khai báo trước khi dùng để tránh lỗi trình biên dịch)
    //==========================================================================
    // ---- Tầng IF ----
    reg  [31:0] pc;                    // Thanh ghi PC: địa chỉ lệnh đang được nạp
    wire [31:0] if_instr;              // Lệnh đọc ra từ bộ nhớ lệnh
    wire [31:0] pc_plus4;              // PC + 4: địa chỉ lệnh kế tiếp
    wire [31:0] pc_next;               // Giá trị PC cho chu kỳ sau

    // ---- Thanh ghi pipeline IF/ID ----
    reg  [31:0] ifid_pc;               // PC của lệnh đang ở tầng ID
    reg  [31:0] ifid_instr;            // Lệnh đang ở tầng ID

    // ---- Tầng ID ----
    wire [6:0]  id_opcode;             // Trường opcode
    wire [4:0]  id_rd;                 // Trường rd (thanh ghi đích)
    wire [2:0]  id_funct3;             // Trường funct3
    wire [4:0]  id_rs1;                // Trường rs1 (thanh ghi nguồn 1)
    wire [4:0]  id_rs2;                // Trường rs2 (thanh ghi nguồn 2)
    wire        id_funct7_5;           // Bit 30 của lệnh
    wire        id_reg_write;          // Tín hiệu điều khiển sinh ra ở tầng ID ...
    wire        id_mem_read;
    wire        id_mem_write;
    wire        id_mem_to_reg;
    wire [1:0]  id_alu_src_a;
    wire        id_alu_src_b;
    wire [3:0]  id_alu_op;
    wire        id_branch;
    wire        id_jal;
    wire        id_jalr;
    wire        id_uses_rs1;
    wire        id_uses_rs2;
    wire [31:0] id_imm;                // Số tức thời đã mở rộng dấu
    wire [31:0] id_rs1_data;           // Giá trị rs1 đọc từ register file
    wire [31:0] id_rs2_data;           // Giá trị rs2 đọc từ register file
    wire        stall;                 // 1 = hazard load-use, cần dừng 1 chu kỳ

    // ---- Thanh ghi pipeline ID/EX ----
    reg  [31:0] idex_pc;               // PC của lệnh ở tầng EX
    reg  [31:0] idex_rs1_data;         // Giá trị rs1 (chưa forwarding)
    reg  [31:0] idex_rs2_data;         // Giá trị rs2 (chưa forwarding)
    reg  [31:0] idex_imm;              // Số tức thời
    reg  [4:0]  idex_rs1;              // Số thứ tự rs1 (cho forwarding)
    reg  [4:0]  idex_rs2;              // Số thứ tự rs2 (cho forwarding)
    reg  [4:0]  idex_rd;               // Số thứ tự rd
    reg  [2:0]  idex_funct3;           // funct3 (dùng cho nhánh, LOAD, STORE)
    reg         idex_reg_write;        // Các tín hiệu điều khiển đi cùng lệnh ...
    reg         idex_mem_read;
    reg         idex_mem_write;
    reg         idex_mem_to_reg;
    reg  [1:0]  idex_alu_src_a;
    reg         idex_alu_src_b;
    reg  [3:0]  idex_alu_op;
    reg         idex_branch;
    reg         idex_jal;
    reg         idex_jalr;

    // ---- Tầng EX ----
    wire [1:0]  fwd_a_sel;             // Chọn nguồn forwarding cho rs1
    wire [1:0]  fwd_b_sel;             // Chọn nguồn forwarding cho rs2
    reg  [31:0] ex_rs1_val;            // Giá trị rs1 sau forwarding
    reg  [31:0] ex_rs2_val;            // Giá trị rs2 sau forwarding
    wire [31:0] alu_in_a;              // Toán hạng A của ALU
    wire [31:0] alu_in_b;              // Toán hạng B của ALU
    wire [31:0] ex_alu_result;         // Kết quả ALU
    wire        ex_cond;               // Kết quả so sánh điều kiện nhánh
    wire [31:0] ex_pc_plus4;           // PC + 4 của lệnh ở EX (địa chỉ quay về của JAL/JALR)
    wire [31:0] ex_branch_target;      // Địa chỉ đích của nhánh / JAL = PC + imm
    wire [31:0] ex_jalr_target;        // Địa chỉ đích của JALR = (rs1 + imm) & ~1
    wire        ex_redirect;           // 1 = lệnh ở EX làm thay đổi luồng chương trình
    wire [31:0] ex_target;             // Địa chỉ PC mới khi ex_redirect = 1
    wire [31:0] ex_result;             // Kết quả "không phải LOAD" của lệnh ở EX

    // ---- Thanh ghi pipeline EX/MEM ----
    reg  [31:0] exmem_alu_result;      // Kết quả ALU / địa chỉ bộ nhớ / địa chỉ quay về
    reg  [31:0] exmem_store_data;      // Dữ liệu cho lệnh STORE (rs2 sau forwarding)
    reg  [4:0]  exmem_rd;              // Thanh ghi đích
    reg  [2:0]  exmem_funct3;          // Kiểu truy cập bộ nhớ
    reg         exmem_reg_write;       // Có ghi thanh ghi không
    reg         exmem_mem_write;       // Có ghi bộ nhớ không
    reg         exmem_mem_to_reg;      // Dữ liệu ghi về lấy từ bộ nhớ không

    // ---- Tầng MEM ----
    wire [31:0] mem_rdata;             // Dữ liệu đọc từ bộ nhớ dữ liệu

    // ---- Thanh ghi pipeline MEM/WB ----
    reg  [31:0] memwb_alu_result;      // Kết quả ALU chuyển tiếp
    reg  [31:0] memwb_rdata;           // Dữ liệu LOAD chuyển tiếp
    reg  [4:0]  memwb_rd;              // Thanh ghi đích
    reg         memwb_reg_write;       // Có ghi thanh ghi không
    reg         memwb_mem_to_reg;      // Chọn dữ liệu bộ nhớ hay kết quả ALU

    // ---- Tầng WB ----
    wire [31:0] wb_data;               // Dữ liệu cuối cùng ghi về register file
    wire        wb_we;                 // Cho phép ghi register file

    //==========================================================================
    // TẦNG IF - NẠP LỆNH
    //==========================================================================
    assign pc_plus4 = pc + 32'd4;                          // Lệnh kế tiếp nằm cách 4 byte
    assign pc_next  = ex_redirect ? ex_target : pc_plus4;  // Nếu EX báo nhảy/rẽ thì lấy địa chỉ đích, không thì PC+4

    instr_mem #(.PROGRAM(PROGRAM)) u_imem (                // Bộ nhớ lệnh (ROM đọc bất đồng bộ)
        .addr  (pc),                                       //   địa chỉ = PC
        .instr (if_instr)                                  //   lệnh đọc ra
    );

    always @(posedge clk) begin                            // Cập nhật PC theo cạnh lên của clk
        if (rst)                                           // Reset
            pc <= 32'd0;                                   //   chương trình bắt đầu tại địa chỉ 0
        else if (en && (ex_redirect || !stall))            // Chạy, và (đang nhảy hoặc không bị stall)
            pc <= pc_next;                                 //   PC chuyển sang giá trị kế tiếp
    end                                                    // Nếu stall: PC giữ nguyên

    assign dbg_pc = pc;                                    // Đưa PC ra ngoài để debug / hiển thị

    //==========================================================================
    // THANH GHI PIPELINE IF/ID
    //==========================================================================
    always @(posedge clk) begin                            // Cập nhật theo cạnh lên của clk
        if (rst) begin                                     // Reset
            ifid_pc    <= 32'd0;                           //   xóa PC
            ifid_instr <= NOP;                             //   lệnh = NOP
        end else if (en) begin                             // Pipeline đang chạy
            if (ex_redirect) begin                         //   Rẽ nhánh/nhảy: lệnh vừa nạp là nạp nhầm
                ifid_pc    <= 32'd0;                       //     xóa (flush)
                ifid_instr <= NOP;                         //     thay bằng NOP
            end else if (!stall) begin                     //   Không stall: nạp lệnh mới
                ifid_pc    <= pc;                          //     lưu PC của lệnh
                ifid_instr <= if_instr;                    //     lưu lệnh
            end                                            //   Nếu stall: giữ nguyên (không gán)
        end
    end

    //==========================================================================
    // TẦNG ID - GIẢI MÃ LỆNH
    //==========================================================================
    assign id_opcode   = ifid_instr[6:0];                  // Tách opcode
    assign id_rd       = ifid_instr[11:7];                 // Tách rd
    assign id_funct3   = ifid_instr[14:12];                // Tách funct3
    assign id_rs1      = ifid_instr[19:15];                // Tách rs1
    assign id_rs2      = ifid_instr[24:20];                // Tách rs2
    assign id_funct7_5 = ifid_instr[30];                   // Tách bit 30 (phân biệt ADD/SUB, SRL/SRA)

    control_unit u_ctrl (                                  // Sinh tín hiệu điều khiển
        .opcode     (id_opcode),
        .funct3     (id_funct3),
        .funct7_5   (id_funct7_5),
        .reg_write  (id_reg_write),
        .mem_read   (id_mem_read),
        .mem_write  (id_mem_write),
        .mem_to_reg (id_mem_to_reg),
        .alu_src_a  (id_alu_src_a),
        .alu_src_b  (id_alu_src_b),
        .alu_op     (id_alu_op),
        .branch     (id_branch),
        .jal        (id_jal),
        .jalr       (id_jalr),
        .uses_rs1   (id_uses_rs1),
        .uses_rs2   (id_uses_rs2)
    );

    imm_gen u_imm (                                        // Sinh số tức thời 32 bit
        .instr (ifid_instr),
        .imm   (id_imm)
    );

    assign wb_we = memwb_reg_write & en;                   // Chỉ ghi register file khi pipeline đang chạy

    reg_file u_regfile (                                   // Tập thanh ghi
        .clk      (clk),
        .we       (wb_we),                                 //   ghi từ tầng WB
        .waddr    (memwb_rd),
        .wdata    (wb_data),
        .raddr1   (id_rs1),                                //   đọc rs1 cho tầng ID
        .raddr2   (id_rs2),                                //   đọc rs2 cho tầng ID
        .rdata1   (id_rs1_data),
        .rdata2   (id_rs2_data),
        .dbg_addr (dbg_reg_addr),                          //   cổng debug
        .dbg_data (dbg_reg_data)
    );

    hazard_unit u_hazard (                                 // Phát hiện hazard load-use
        .ex_mem_read (idex_mem_read),                      //   lệnh ở EX là LOAD?
        .ex_rd       (idex_rd),                            //   rd của lệnh ở EX
        .id_rs1      (id_rs1),                             //   rs1 của lệnh ở ID
        .id_rs2      (id_rs2),                             //   rs2 của lệnh ở ID
        .id_uses_rs1 (id_uses_rs1),
        .id_uses_rs2 (id_uses_rs2),
        .stall       (stall)
    );

    //==========================================================================
    // THANH GHI PIPELINE ID/EX
    //==========================================================================
    always @(posedge clk) begin                            // Cập nhật theo cạnh lên của clk
        if (rst || (en && (ex_redirect || stall))) begin   // Reset, hoặc cần chèn "bong bóng" (flush / stall)
            idex_pc         <= 32'd0;                      //   xóa toàn bộ trường
            idex_rs1_data   <= 32'd0;
            idex_rs2_data   <= 32'd0;
            idex_imm        <= 32'd0;
            idex_rs1        <= 5'd0;
            idex_rs2        <= 5'd0;
            idex_rd         <= 5'd0;
            idex_funct3     <= 3'd0;
            idex_reg_write  <= 1'b0;                       //   mọi tín hiệu điều khiển = 0 -> bong bóng không làm gì
            idex_mem_read   <= 1'b0;
            idex_mem_write  <= 1'b0;
            idex_mem_to_reg <= 1'b0;
            idex_alu_src_a  <= 2'b00;
            idex_alu_src_b  <= 1'b0;
            idex_alu_op     <= 4'b0000;
            idex_branch     <= 1'b0;
            idex_jal        <= 1'b0;
            idex_jalr       <= 1'b0;
        end else if (en) begin                             // Chạy bình thường: chuyển lệnh từ ID sang EX
            idex_pc         <= ifid_pc;
            idex_rs1_data   <= id_rs1_data;
            idex_rs2_data   <= id_rs2_data;
            idex_imm        <= id_imm;
            idex_rs1        <= id_rs1;
            idex_rs2        <= id_rs2;
            idex_rd         <= id_rd;
            idex_funct3     <= id_funct3;
            idex_reg_write  <= id_reg_write;
            idex_mem_read   <= id_mem_read;
            idex_mem_write  <= id_mem_write;
            idex_mem_to_reg <= id_mem_to_reg;
            idex_alu_src_a  <= id_alu_src_a;
            idex_alu_src_b  <= id_alu_src_b;
            idex_alu_op     <= id_alu_op;
            idex_branch     <= id_branch;
            idex_jal        <= id_jal;
            idex_jalr       <= id_jalr;
        end
    end

    //==========================================================================
    // TẦNG EX - THỰC THI
    //==========================================================================
    forwarding_unit u_fwd (                                // Quyết định lấy toán hạng từ đâu
        .ex_rs1        (idex_rs1),
        .ex_rs2        (idex_rs2),
        .mem_rd        (exmem_rd),                         //   lệnh ở tầng MEM
        .mem_reg_write (exmem_reg_write),
        .wb_rd         (memwb_rd),                         //   lệnh ở tầng WB
        .wb_reg_write  (memwb_reg_write),
        .forward_a     (fwd_a_sel),
        .forward_b     (fwd_b_sel)
    );

    always @(*) begin                                      // Mux forwarding cho rs1 và rs2
        case (fwd_a_sel)
            2'b10:   ex_rs1_val = exmem_alu_result;        //   lấy kết quả của lệnh ở MEM
            2'b01:   ex_rs1_val = wb_data;                 //   lấy kết quả của lệnh ở WB
            default: ex_rs1_val = idex_rs1_data;           //   dùng giá trị đọc từ register file
        endcase
        case (fwd_b_sel)
            2'b10:   ex_rs2_val = exmem_alu_result;        //   lấy kết quả của lệnh ở MEM
            2'b01:   ex_rs2_val = wb_data;                 //   lấy kết quả của lệnh ở WB
            default: ex_rs2_val = idex_rs2_data;           //   dùng giá trị đọc từ register file
        endcase
    end

    assign alu_in_a = (idex_alu_src_a == 2'b01) ? idex_pc :        // AUIPC: A = PC
                      (idex_alu_src_a == 2'b10) ? 32'd0   :        // LUI  : A = 0
                                                  ex_rs1_val;      // Còn lại: A = rs1
    assign alu_in_b = idex_alu_src_b ? idex_imm : ex_rs2_val;      // B = imm hoặc rs2

    alu u_alu (                                            // Khối ALU
        .a      (alu_in_a),
        .b      (alu_in_b),
        .alu_op (idex_alu_op),
        .result (ex_alu_result)
    );

    branch_unit u_branch (                                 // So sánh điều kiện nhánh
        .a      (ex_rs1_val),
        .b      (ex_rs2_val),
        .funct3 (idex_funct3),
        .cond   (ex_cond)
    );

    assign ex_pc_plus4      = idex_pc + 32'd4;                         // Địa chỉ quay về của JAL/JALR
    assign ex_branch_target = idex_pc + idex_imm;                      // Đích của nhánh và JAL
    assign ex_jalr_target   = (ex_rs1_val + idex_imm) & 32'hFFFF_FFFE; // Đích của JALR (xóa bit 0 theo đặc tả)
    assign ex_redirect      = (idex_branch & ex_cond) | idex_jal | idex_jalr;  // Có đổi luồng chương trình không
    assign ex_target        = idex_jalr ? ex_jalr_target : ex_branch_target;   // Chọn địa chỉ đích
    assign ex_result        = (idex_jal | idex_jalr) ? ex_pc_plus4 : ex_alu_result; // JAL/JALR ghi PC+4 vào rd

    //==========================================================================
    // THANH GHI PIPELINE EX/MEM
    //==========================================================================
    always @(posedge clk) begin                            // Cập nhật theo cạnh lên của clk
        if (rst) begin                                     // Reset
            exmem_alu_result <= 32'd0;
            exmem_store_data <= 32'd0;
            exmem_rd         <= 5'd0;
            exmem_funct3     <= 3'd0;
            exmem_reg_write  <= 1'b0;
            exmem_mem_write  <= 1'b0;
            exmem_mem_to_reg <= 1'b0;
        end else if (en) begin                             // Chạy: chuyển lệnh từ EX sang MEM
            exmem_alu_result <= ex_result;                 //   kết quả / địa chỉ
            exmem_store_data <= ex_rs2_val;                //   dữ liệu STORE (đã forwarding)
            exmem_rd         <= idex_rd;
            exmem_funct3     <= idex_funct3;
            exmem_reg_write  <= idex_reg_write;
            exmem_mem_write  <= idex_mem_write;
            exmem_mem_to_reg <= idex_mem_to_reg;
        end
    end

    //==========================================================================
    // TẦNG MEM - TRUY CẬP BỘ NHỚ DỮ LIỆU
    //==========================================================================
    data_mem u_dmem (                                      // Bộ nhớ dữ liệu
        .clk    (clk),
        .we     (exmem_mem_write & en),                    //   chỉ ghi khi pipeline đang chạy
        .funct3 (exmem_funct3),
        .addr   (exmem_alu_result),
        .wdata  (exmem_store_data),
        .rdata  (mem_rdata)
    );

    //==========================================================================
    // THANH GHI PIPELINE MEM/WB
    //==========================================================================
    always @(posedge clk) begin                            // Cập nhật theo cạnh lên của clk
        if (rst) begin                                     // Reset
            memwb_alu_result <= 32'd0;
            memwb_rdata      <= 32'd0;
            memwb_rd         <= 5'd0;
            memwb_reg_write  <= 1'b0;
            memwb_mem_to_reg <= 1'b0;
        end else if (en) begin                             // Chạy: chuyển lệnh từ MEM sang WB
            memwb_alu_result <= exmem_alu_result;
            memwb_rdata      <= mem_rdata;
            memwb_rd         <= exmem_rd;
            memwb_reg_write  <= exmem_reg_write;
            memwb_mem_to_reg <= exmem_mem_to_reg;
        end
    end

    //==========================================================================
    // TẦNG WB - GHI KẾT QUẢ VỀ THANH GHI
    //==========================================================================
    assign wb_data = memwb_mem_to_reg ? memwb_rdata : memwb_alu_result;  // LOAD lấy từ bộ nhớ, còn lại lấy từ ALU

endmodule                                                  // Kết thúc module riscv_core
