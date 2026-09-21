// -----------------------------------------------------------------------------
// rv32i_core.v — Single-cycle RV32I subset
//
// Supports: LUI, AUIPC, JAL, JALR, BEQ/BNE/BLT/BGE/BLTU/BGEU,
//           LW, SW, ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI,
//           ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND.
//
// Memories: 256-word instruction ROM, 256-word data RAM (word-addressed).
// x0 is hardwired to 0.
// -----------------------------------------------------------------------------
module rv32i_core (
    input  wire        clk,
    input  wire        rst_n,
    output wire [31:0] pc_out,
    output wire [31:0] instr_out,
    output wire [31:0] reg_x1,
    output wire [31:0] reg_x2,
    output wire [31:0] reg_x3
);
    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------
    reg [31:0] pc;
    reg [31:0] imem    [0:255];
    reg [31:0] dmem    [0:255];
    reg [31:0] regfile [0:31];

    wire [31:0] instr    = imem[pc[9:2]];
    wire [31:0] pc_plus4 = pc + 32'd4;

    // -------------------------------------------------------------------------
    // Decode
    // -------------------------------------------------------------------------
    wire [6:0] opcode = instr[6:0];
    wire [4:0] rd     = instr[11:7];
    wire [2:0] funct3 = instr[14:12];
    wire [4:0] rs1    = instr[19:15];
    wire [4:0] rs2    = instr[24:20];
    wire [6:0] funct7 = instr[31:25];

    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7],
                         instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12],
                         instr[20], instr[30:21], 1'b0};

    localparam OP_R      = 7'b0110011;
    localparam OP_I      = 7'b0010011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;

    // -------------------------------------------------------------------------
    // Register read (x0 = 0)
    // -------------------------------------------------------------------------
    wire [31:0] rs1_val = (rs1 == 5'd0) ? 32'd0 : regfile[rs1];
    wire [31:0] rs2_val = (rs2 == 5'd0) ? 32'd0 : regfile[rs2];

    // -------------------------------------------------------------------------
    // ALU
    // -------------------------------------------------------------------------
    wire use_imm = (opcode == OP_I) || (opcode == OP_LOAD) ||
                   (opcode == OP_STORE) || (opcode == OP_JALR);
    wire [31:0] alu_b = use_imm ?
                        ((opcode == OP_STORE) ? imm_s : imm_i) : rs2_val;

    // SUB only for R-type ADD/SUB with funct7[5]=1; SRA when funct7[5]=1 on shift-right
    wire alu_sub = (opcode == OP_R) && funct7[5] && (funct3 == 3'b000);
    wire alu_sra = ((opcode == OP_R) || (opcode == OP_I)) &&
                    funct7[5] && (funct3 == 3'b101);

    reg [31:0] alu_out;
    always @(*) begin
        case (funct3)
            3'b000: alu_out = alu_sub ? (rs1_val - alu_b) : (rs1_val + alu_b);
            3'b001: alu_out = rs1_val << alu_b[4:0];
            3'b010: alu_out = ($signed(rs1_val) < $signed(alu_b)) ? 32'd1 : 32'd0;
            3'b011: alu_out = (rs1_val < alu_b) ? 32'd1 : 32'd0;
            3'b100: alu_out = rs1_val ^ alu_b;
            3'b101: alu_out = alu_sra ? ($signed(rs1_val) >>> alu_b[4:0])
                                      : (rs1_val >> alu_b[4:0]);
            3'b110: alu_out = rs1_val | alu_b;
            3'b111: alu_out = rs1_val & alu_b;
            default: alu_out = 32'd0;
        endcase
    end

    // -------------------------------------------------------------------------
    // Memory address / load
    // -------------------------------------------------------------------------
    wire [31:0] mem_addr  = rs1_val + ((opcode == OP_STORE) ? imm_s : imm_i);
    wire [31:0] load_data = dmem[mem_addr[9:2]];

    // -------------------------------------------------------------------------
    // Branch
    // -------------------------------------------------------------------------
    reg branch_taken;
    always @(*) begin
        case (funct3)
            3'b000:  branch_taken = (rs1_val == rs2_val);
            3'b001:  branch_taken = (rs1_val != rs2_val);
            3'b100:  branch_taken = ($signed(rs1_val) <  $signed(rs2_val));
            3'b101:  branch_taken = ($signed(rs1_val) >= $signed(rs2_val));
            3'b110:  branch_taken = (rs1_val <  rs2_val);
            3'b111:  branch_taken = (rs1_val >= rs2_val);
            default: branch_taken = 1'b0;
        endcase
    end

    wire [31:0] pc_next =
        ((opcode == OP_BRANCH) && branch_taken) ? (pc + imm_b) :
         (opcode == OP_JAL)                     ? (pc + imm_j) :
         (opcode == OP_JALR)                    ? ((rs1_val + imm_i) & ~32'd1) :
                                                   pc_plus4;

    // -------------------------------------------------------------------------
    // Writeback
    // -------------------------------------------------------------------------
    reg [31:0] wb_data;
    always @(*) begin
        case (opcode)
            OP_LOAD:              wb_data = load_data;
            OP_JAL, OP_JALR:      wb_data = pc_plus4;
            OP_LUI:               wb_data = imm_u;
            OP_AUIPC:             wb_data = pc + imm_u;
            default:              wb_data = alu_out;
        endcase
    end

    wire reg_write = (opcode == OP_R) || (opcode == OP_I) ||
                     (opcode == OP_LOAD) || (opcode == OP_JAL) ||
                     (opcode == OP_JALR) || (opcode == OP_LUI) ||
                     (opcode == OP_AUIPC);

    // -------------------------------------------------------------------------
    // Sequential update
    // -------------------------------------------------------------------------
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'd0;
            for (i = 0; i < 32; i = i + 1) regfile[i] <= 32'd0;
        end else begin
            pc <= pc_next;
            if (reg_write && (rd != 5'd0))
                regfile[rd] <= wb_data;
            if (opcode == OP_STORE)
                dmem[mem_addr[9:2]] <= rs2_val;
        end
    end

    assign pc_out    = pc;
    assign instr_out = instr;
    assign reg_x1    = regfile[1];
    assign reg_x2    = regfile[2];
    assign reg_x3    = regfile[3];

    // -------------------------------------------------------------------------
    // Program: compute sum(1..10) = 55, store to dmem[0]
    //
    //   addi x1, x0, 0     ; sum = 0
    //   addi x2, x0, 1     ; i   = 1
    //   addi x3, x0, 11    ; lim = 11
    // loop:
    //   bge  x2, x3, done  ; if i >= lim, exit
    //   add  x1, x1, x2    ; sum += i
    //   addi x2, x2, 1     ; i++
    //   jal  x0, loop
    // done:
    //   sw   x1, 0(x0)     ; mem[0] = sum
    //   jal  x0, 0         ; halt (spin)
    // -------------------------------------------------------------------------
    initial begin
        imem[0] = 32'h00000093;  // addi x1, x0, 0
        imem[1] = 32'h00100113;  // addi x2, x0, 1
        imem[2] = 32'h00B00193;  // addi x3, x0, 11
        imem[3] = 32'h00315863;  // bge  x2, x3, +16
        imem[4] = 32'h002080B3;  // add  x1, x1, x2
        imem[5] = 32'h00110113;  // addi x2, x2, 1
        imem[6] = 32'hFF5FF06F;  // jal  x0, -12
        imem[7] = 32'h00102023;  // sw   x1, 0(x0)
        imem[8] = 32'h0000006F;  // jal  x0, 0   (halt)
        for (i = 9; i < 256; i = i + 1) imem[i] = 32'h00000013; // NOP
        for (i = 0; i < 256; i = i + 1) dmem[i] = 32'd0;
    end
endmodule
