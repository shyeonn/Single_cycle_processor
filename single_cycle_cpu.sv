/* ********************************************
 *	COSE222 Lab #3
 *
 *	Module: top design of the single-cycle CPU (single_cycle_cpu.sv)
 *  - Top design of the single-cycle CPU
 *
 *  Author: Gunjae Koo (gunjaekoo@korea.ac.kr)
 *
 * ********************************************
 */

`timescale 1ns/1ps

module single_cycle_cpu
#(  parameter IMEM_DEPTH = 1024,    // imem depth (default: 1024 entries = 4 KB)
              IMEM_ADDR_WIDTH = 10,
              REG_WIDTH = 32,
              DMEM_DEPTH = 1024,    // dmem depth (default: 1024 entries = 8 KB)
              DMEM_ADDR_WIDTH = 10 )
(
    input           clk,            // System clock
    input           reset_b         // Asychronous negative reset
);

    // Wires for datapath elements
    logic   [IMEM_ADDR_WIDTH-1:0]   imem_addr;
    logic   [31:0]  inst;   // instructions = an output of ????

    logic   [4:0]   rs1, rs2, rd;    // register numbers
    logic   [REG_WIDTH-1:0] rd_din;
    logic           reg_write;
    logic   [REG_WIDTH-1:0] rs1_dout, rs2_dout;

    logic   [REG_WIDTH-1:0] alu_in1, alu_in2;
    logic   [3:0]   alu_control;    // ALU control signal
    logic   [REG_WIDTH-1:0] alu_result;
    logic           alu_zero;
    logic           alu_sign;
    logic	    alu_less_u;

    logic   [DMEM_ADDR_WIDTH-1:0]    dmem_addr;
    logic   [31:0]  dmem_din, dmem_dout;
    logic           mem_read, mem_write;

    // -------------------------------------------------------------------
    /* Main control unit:
     * Main control unit generates control signals for datapath elements
     * The control signals are determined by decoding instructions
     * Generating control signals using opcode = inst[6:0]
     */
    logic   [6:0]   opcode;
    logic   [7:0]   branch;
    logic           alu_src, mem_to_reg;
    logic   [1:0]   alu_op;
    logic   [2:0]   funct3;
    //logic         mem_read, mem_write, reg_write; // declared above
    // Note for Lab #3
    // The branch control signal has 4-bits since this processor supports beq, bne, blt, and bge
    // Each bit of the branch control signal represents the corresponding branch instruction
    // i.e., branch[0] = beq, branch[1] = bne, branch[2] = blt, branch[3] = bge

    // COMPLETE THE MAIN CONTROL UNIT HERE
    assign opcode = inst[6:0];
	assign funct3 = inst[14:12];
	assign funct7 = inst[31:25];
    assign branch = 'b1 << funct3; 

    assign u_type = ~|(opcode ^ 7'b0010111) | ~|(opcode ^ 7'b0110111);
    assign jump = ~|(opcode ^ 7'b1100111) | ~|(opcode ^ 7'b1101111);

    assign mem_read = ~|(opcode ^ 7'b0000011);    // ld
    assign mem_write = ~|(opcode ^ 7'b0100011);   // sd
    assign mem_to_reg = mem_read; //ld
    // ld, r-type, i-type, U or jump type
    assign reg_write = mem_read |  ~|(opcode ^ 7'b0110011) | ~|(opcode ^ 7'b0010011) | u_type | jump; 
    assign alu_src = mem_read | ~|(opcode ^ 7'b0100011) | ~|(opcode ^ 7'b0010011);   // ld, or i-type

    assign alu_op[0] = ~|(opcode ^ 7'b1100011); //branch 
    assign alu_op[1] = ~|(opcode ^ 7'b0110011) | ~|(opcode ^ 7'b0010011);    // r-type or i-type


    // --------------------------------------------------------------------

    // --------------------------------------------------------------------
    /* ALU control unit:
     * ALU control unit generate alu_control signal which selects ALU operations
     * Generating control signals using alu_op, funct7, and funct3 fileds
     */
    logic   [6:0]   funct7;
    //logic   [2:0]   funct3;   // declared above

    // COMPLETE THE ALU CONTROL UNIT HERE
	always_comb begin
		case ({alu_op, funct3}) 
			{2'b00, funct3}: alu_control = 4'b0010; // ld/st
			{2'b01, funct3}: alu_control = 4'b0110; // br
			{2'b10, 3'b000}: alu_control = |(opcode ^ 7'b0010011) & funct7[5] ? 4'b0110 : 4'b0010; // sub / add
			{2'b10, 3'b001}: alu_control = 4'b1000; //sl
			{2'b10, 3'b010}: alu_control = 4'b0110; //set less then
			{2'b10, 3'b011}: alu_control = 4'b0110; //set less then unsigned
			{2'b10, 3'b101}: alu_control = funct7[5] ? 4'b1011 : 4'b1010; //sr(logi) / sr(ari)
			{2'b10, 3'b100}: alu_control = 4'b0011; //xor
			{2'b10, 3'b110}: alu_control = 4'b0001; //or
			{2'b10, 3'b111}: alu_control = 4'b0000; //and
		endcase
	end

    // ---------------------------------------------------------------------


    // ---------------------------------------------------------------------
    /* Immediate generator:
     * Generating immediate value from inst[31:0]
     * We require immediate type data for load, store, i-type, and branch instructions
     */
    logic   [REG_WIDTH-1:0]  imm32;
    logic   [REG_WIDTH-1:0]  imm32_branch;  // imm32 left shifted by 1
    logic   [11:0]  imm12;  // 12-bit immediate value extracted from inst
    logic   [REG_WIDTH-2:0]  imm_jal;

    // COMPLETE IMMEDIATE GENERATOR HERE
	always_comb begin
		case (opcode)
			7'b0000011 : imm12 = inst[31:20]; //ld
			7'b0100011 : imm12 = {inst[31:25], inst[11:7]}; //st
			7'b0010011 : imm12 = inst[31:20]; //I
			7'b1100111 : imm12 = inst[31:20]; //I(JALR)
			7'b1100011 : imm12 = {inst[31], inst[7], inst[30:25], inst[11:8]}; //SB
		endcase 
	end
	assign imm_jal = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21]}; //JAL

	assign imm32 = (jump & opcode[3]) ? imm_jal : $signed({{20{imm12[11]}}, imm12});
	assign imm32_branch = imm32<<1;

    // ----------------------------------------------------------------------

    // Program counter
    logic   [31:0]  pc_curr, pc_next;
    logic           pc_next_sel;    // selection signal for pc_next
    logic   [31:0]  pc_next_plus4, pc_next_branch;
    logic   [31:0]  pc_imm;


    assign pc_next_plus4 = pc_curr + 4;

    always_ff @ (posedge clk or negedge reset_b) begin
        if (~reset_b) begin
            pc_curr <= 'b0;
        end else begin
            pc_curr <= pc_next;
        end
    end


    // MUXes:
    // COMPLETE MUXES HERE
    // PC_NEXT
    assign pc_next_sel = jump | (alu_op[0] & (
	  (branch[0] & alu_zero) |
	  (branch[1] & !alu_zero) |
	  ((branch[4]) & (!alu_zero & alu_sign)) |
	  ((branch[5]) & !(!alu_zero & alu_sign)) |
	  ((branch[6]) & alu_less_u) |
	  ((branch[7]) & !alu_less_u)
	  ));

    assign pc_next = (pc_next_sel) ? pc_next_branch: pc_next_plus4; // if branch is taken, pc_next_sel=1'b1
    assign pc_next_branch = pc_curr + ((jump & !opcode[3]) ? imm32 : imm32_branch);  // UJ / SB

    // ALU inputs
    assign alu_in1 = rs1_dout;
    assign alu_in2 = alu_src ? imm32 : rs2_dout;

    // RF din
    logic comp_bit, is_comp;

    assign is_comp = alu_op[1] & ~|(funct3[2:1] ^ 2'b01);
    assign comp_bit = funct3[0] ? alu_less_u : (alu_sign & !alu_zero);

    always_comb begin
	case ({mem_to_reg, is_comp, u_type, jump})
	    4'b1000: rd_din = dmem_dout;
	    4'b0100: rd_din = comp_bit;
	    4'b0010: rd_din = opcode[5] ? imm32 + pc_curr : imm32; // auipc / lui
	    4'b0001: rd_din = pc_next_plus4;
	    4'b0000: rd_din = alu_result;
	endcase 
    end

    // COMPLETE CONNECTIONS HERE
    // imem
    assign imem_addr = pc_curr[9:0];

    // regfile
    assign rs1 = inst[19:15];
    assign rs2 = inst[24:20];
    assign rd = inst[11:7];

    // dmem
    assign dmem_addr = alu_result[9:0];
    assign dmem_din = rs2_dout;
 

    // ----------------------------------------------------------------------

    // Memory control unit (for unaligned access)
	logic [1:0]		access_size;
	logic [31:0]	dmem_dout_raw;
	//
	//
	assign access_size = funct3[1:0];


	always_comb begin
		case (access_size)
		  2'b00 : dmem_dout = funct3[2] ? {24'b0, dmem_dout_raw[7:0]} : {{24{dmem_dout_raw[7]}}, dmem_dout_raw[7:0]};
		  2'b01 : dmem_dout = funct3[2] ? {16'b0, dmem_dout_raw[15:0]} : {{16{dmem_dout_raw[15]}}, dmem_dout_raw[15:0]};
		  2'b10 : dmem_dout = dmem_dout_raw;
		endcase 
	end

    // -----------------------------------------------------------------------
    /* Instantiation of datapath elements
     * All input/output ports should be connected
     */
    
    // IMEM
    imem #(
        .IMEM_DEPTH         (IMEM_DEPTH),
        .IMEM_ADDR_WIDTH    (IMEM_ADDR_WIDTH)
    ) u_imem_0 (
        .addr               ( imem_addr     ),
        .dout               ( inst     )
    );

    // REGFILE
	regfile #(
		.REG_WIDTH			(REG_WIDTH)
	) u_regfile_0 (
		.clk				(clk),
		.rs1				(rs1),
		.rs2				(rs2),
		.rd					(rd),
		.rd_din				(rd_din),
		.reg_write			(reg_write),
		.rs1_dout			(rs1_dout),
		.rs2_dout			(rs2_dout)
	);

    // ALU
	alu #(
		.REG_WIDTH			(REG_WIDTH)
	) u_alu_0 (
		.in1				(alu_in1),
		.in2				(alu_in2),
		.alu_control		(alu_control),
		.result				(alu_result),
		.zero				(alu_zero),
		.sign				(alu_sign),
		.less_u				(alu_less_u)
	);

//    // DMEM (aligned)
//	dmem #(
//		.DMEM_DEPTH			(DMEM_DEPTH),
//		.DMEM_ADDR_WIDTH	(DMEM_ADDR_WIDTH)
//	) u_dmem_0 (
//		.clk				(clk),
//		.addr				(dmem_addr),
//		.din				(dmem_din),
//		.mem_read			(mem_read),
//		.mem_write			(mem_write),
//		.dout				(dmem_dout)
//	);

    // DMEM (unaligned)
	dmem #(
		.DMEM_DEPTH			(DMEM_DEPTH),
		.DMEM_ADDR_WIDTH	(DMEM_ADDR_WIDTH)
	) u_dmem_0 (
		.clk				(clk),
		.addr				(dmem_addr),
		.rd_en				(mem_read),
		.wr_en				(mem_write),
		.sz					(access_size),
		.din				(dmem_din),
		.dout				(dmem_dout_raw)
	);

endmodule
