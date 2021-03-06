`timescale 1ns / 1ps

// File: pipeline.v
// The top module for the whole pipeline

`include "common.vh"

module pipeline (
    // Just to simpilfy RTL generation,
    input clk,         // the global clock
    input reset,       // the global reset
    input [7:0] intr,   // 8 hardware interruption
    output [31:0] mem_pc_out
);

parameter DATA_WIDTH = 32;

////////////////////////////////////////////////////////////////////////////////
//
//
//  Sinal declaration
//
////////////////////////////////////////////////////////////////////////////////

wire [DATA_WIDTH - 1 : 0] predicted_pc;
wire bpu_w_en;                           // Whether the PC in EX is expected

wire [DATA_WIDTH - 1 : 0] jmp;        // Absolute jump
wire [DATA_WIDTH - 1 : 0] jr;         // Jump to $31
wire [DATA_WIDTH - 1 : 0] cu_vector;  // Entry for exception handling
wire [DATA_WIDTH - 1 : 0] epc;        // Eret
wire [DATA_WIDTH - 1 : 0] target;     // Control harzard

reg [DATA_WIDTH - 1 : 0] pc_in;       // Next pc to go into the pipeline

wire [DATA_WIDTH - 1 : 0] pc_out;  // PC to fetch instruction

////////////////////////////////////////////////////////////////////////////
//  Instruction
//  I-cache and D-cache are implemented together, it will be instanciated
//  later.
////////////////////////////////////////////////////////////////////////////

wire [DATA_WIDTH - 1 : 0] ic_data_out;

wire [DATA_WIDTH - 1 : 0] ifid_pc, ifid_pc_4;
wire [DATA_WIDTH - 1 : 0] ifid_jump_addr;
wire [DATA_WIDTH - 1 : 0] ifid_instr;
wire [`REG_ADDR_BUS] ifid_rs_addr, ifid_rt_addr, ifid_rd_addr;
wire [`IMM_BUS] ifid_imm;

wire id_jr;
wire id_jump;
wire idex_syscall;
wire idex_eret;
wire [1:0] id_imm_ext;
wire idex_mem_w;
wire idex_mem_r;
wire idex_reg_w;
wire idex_branch;
wire [2:0] idex_condition;
wire idex_B_sel;
wire [3:0] idex_ALU_op;
wire [4:0] idex_shamt;
wire idex_shamt_sel;
wire [1:0] idex_shift_op;
wire [2:0] idex_load_sel;
wire [2:0] idex_store_sel;
wire [1:0] id_rd_addr_sel;
wire [4:0] idex_cp0_dest_addr;
wire id_rt_addr_sel;
wire id_rt_data_sel;
wire [`REG_ADDR_BUS] id_cp0_src_addr;
wire [1:0] idex_exres_sel;
wire idex_movn;
wire idex_movz;

reg [`REG_ADDR_BUS] id_rt_addr;

wire [DATA_WIDTH - 1 : 0] wb_data_in;
wire [DATA_WIDTH - 1 : 0] id_rs_out;
wire [DATA_WIDTH - 1 : 0] id_rt_out;

reg [`REG_ADDR_BUS] id_rd_addr;

wire [DATA_WIDTH - 1 : 0] id_gpr_rs = id_rs_out;  // For name consistence
reg [DATA_WIDTH - 1 : 0] id_gpr_rt;
wire [DATA_WIDTH - 1 : 0] cp0_data;

wire ex_movz;
wire ex_movn;
wire ex_mem_w;
wire ex_mem_r;
wire ex_reg_w;
wire ex_branch;
wire [2:0] ex_condition;
wire ex_of_w_disen;
wire [1:0] ex_exres_sel;
wire ex_B_sel;
wire [3:0] ex_ALU_op;
wire ex_shamt_sel;
wire [4:0] ex_shamt;
wire [1:0] ex_shift_op;
wire [`DATA_BUS] ex_imm_ext;
wire [`PC_BUS] ex_pc;
wire [`PC_BUS] ex_pc_4;
wire [`REG_ADDR_BUS] ex_rd_addr;
wire [2:0] ex_load_sel;
wire [2:0] ex_store_sel;
wire [`DATA_BUS] ex_op_A;
wire [`DATA_BUS] ex_op_B;
wire [`REG_ADDR_BUS] ex_rs_addr;
wire [`REG_ADDR_BUS] ex_rt_addr;
wire [`REG_ADDR_BUS] ex_cp0_dst_addr;
wire ex_cp0_w_en;
wire ex_syscall;
wire ex_eret;

wire [DATA_WIDTH - 1 : 0] imm_ext;

// Result after various selections
reg [`DATA_BUS] operand_A_after_forwarding;
reg [`DATA_BUS] operand_A_after_selection;
reg [`DATA_BUS] operand_B_after_forwarding;
reg [`DATA_BUS] operand_B_after_selection;
reg [`DATA_BUS] exec_result;
reg [4:0] shamt_after_sel;

// Exec result candidates
wire [`DATA_BUS] alu_out;
wire [`DATA_BUS] shifter_out;

wire ex_jr;  // JR indicator
wire [`PC_BUS] branch_addr = (ex_jr == 1) ? alu_out : ex_pc_4 + (ex_imm_ext<<2);

// Forwarding selectors
wire [1:0] A_sel;
wire [1:0] B_sel;
// Forwarding result
wire [`DATA_BUS] input_A;
wire [`DATA_BUS] input_B;

wire ex_less;      // High if A < B
wire ex_overflow;  // High if A op B > MAX or A op B < MIN
wire ex_zero;      // High if A op B == 0

wire [3:0] ex_reg_byte_w_en;
wire [3:0] ex_mem_byte_w_en;
wire [`DATA_BUS] ex_aligned_rt_data;

// MEM pc
wire [`PC_BUS] mem_pc;
wire [`PC_BUS] mem_pc_4;
// MEM enable
wire mem_mem_w;
wire mem_mem_r;
wire mem_reg_w;
wire [3:0] mem_reg_byte_w_en;
wire [3:0] mem_mem_byte_w_en;
// MEM register related
wire [`REG_ADDR_BUS] mem_rd_addr;
wire [`DATA_BUS] mem_alu_res;
// MEM memory related
wire [`REG_ADDR_BUS] mem_cp0_dst_addr;
// The data from EX, used in the MEM segment.
// It has been aligned in the EX segment, and will provide data to MEMWB and Memory when SW* is excuted.
wire [`DATA_BUS] mem_aligned_rt_data;
wire [`DATA_BUS] mem_aligned_mem_data ;
// MEM control
wire mem_branch;
wire mem_lf;
wire mem_zf;
wire [2:0] mem_load_sel;
wire [2:0] mem_store_sel;
wire [2:0] mem_condition;
wire [`PC_BUS] mem_target;
// MEM exception
wire mem_cp0_w_en;
wire mem_syscall;
wire mem_eret;

// Normal pipeline part
wire wb_mem_r;                    // High if read from memory
wire wb_reg_w;                    // High if can write to gpr
wire [3:0] wb_reg_byte_w_en;      // High if this byte can be written
wire [`DATA_BUS] wb_ex_data;      // Data from EX
wire [`DATA_BUS] wb_mem_data;     // Data from MEM
wire [`REG_ADDR_BUS] wb_rd_addr;  // Write to this register

// Exception part
wire [`REG_ADDR_BUS] wb_cp0_dst_addr;
wire wb_cp0_w_en;

// Output
wire [`DATA_BUS] memwb_data = (wb_mem_r) ? wb_mem_data : wb_ex_data;

wire [`PC_BUS] mem_final_target;  // output from final_target to control unit

wire [`DATA_BUS] mem_data;  // output from cpu_interface.data_out to load_shifter.mem_data

////////////////////////////////////////////////////////////////////////////
//
//  IF
//
////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////
//  BPU
////////////////////////////////////////////////////////////////////////////

wire [`PC_BUS] if_pc_4;

BPU bpu (
    // Input
    .clk          ( clk ),
    .reset        ( reset ),
    .bpu_w_en     ( bpu_w_en ),
    .current_pc   ( if_pc_4 ),  // When reseted, ifid is flushed, and ifid_pc_4 is zero.
    .tag_pc       ( mem_pc ),
    .next_pc      ( mem_final_target ),
    // Output
    .predicted_pc ( predicted_pc )
);

wire [3:0] cu_pc_src;  // Select pc source, get data from control unit.

always @(*) begin
    case (cu_pc_src)
    3'd0: pc_in = jmp;
    3'd1: pc_in = jr;
    3'd2: pc_in = cu_vector;
    3'd3: pc_in = epc;
    3'd4: pc_in = target;
    3'd5: pc_in = predicted_pc;
    default: pc_in = 0;
    endcase
end

assign target = mem_final_target;


////////////////////////////////////////////////////////////////////////////
//  PC register
////////////////////////////////////////////////////////////////////////////

PC PC (
    .clk    ( clk ),
    .reset  ( reset ),
    .stall  ( cu_pc_stall ),
    .pc_in  ( pc_in ),
    .pc_out ( pc_out )
);

////////////////////////////////////////////////////////////////////////////
//  IFID register
////////////////////////////////////////////////////////////////////////////

assign jmp = ifid_jump_addr;
assign jr = id_rs_out;
assign if_pc_4 = (reset) ? 0 : pc_out + 4;  // Start from zero

wire id_nop;  // Indicate that the current instr in ID is nop
              // The ifid does not have a input nop-indicator,
              // because PC is always right in the next cycle.

ifid_reg ifid (
    // Input
    .clk            ( clk ),
    .reset          ( reset ),
    .cu_stall       ( cu_ifid_stall ),
    .cu_flush       ( cu_ifid_flush ),
    .pc             ( pc_out ),
    .pc_4           ( if_pc_4 ),
    .instr          ( ic_data_out ),
    // Output
    .id_nop         ( id_nop ),
    .ifid_pc        ( ifid_pc ),
    .ifid_pc_4      ( ifid_pc_4 ),
    .ifid_instr     ( ifid_instr ),
    .ifid_jump_addr ( ifid_jump_addr ),
    .ifid_rs_addr   ( ifid_rs_addr ),
    .ifid_rt_addr   ( ifid_rt_addr ),
    .ifid_rd_addr   ( ifid_rd_addr ),
    .ifid_imm       ( ifid_imm )
);

////////////////////////////////////////////////////////////////////////////
//
//  ID
//
////////////////////////////////////////////////////////////////////////////

decoder decoder(
    // Input
    .ifid_instr(ifid_instr),
    // Output
    .idex_mem_w(idex_mem_w),
    .idex_mem_r(idex_mem_r),
    .idex_reg_w(idex_reg_w),
    .idex_branch(idex_branch),
    .idex_condition(idex_condition),
    .idex_B_sel(idex_B_sel),
    .idex_ALU_op(idex_ALU_op),
    .idex_shamt(idex_shamt),
    .idex_shamt_sel(idex_shamt_sel),
    .idex_shift_op(idex_shift_op),
    .idex_load_sel(idex_load_sel),
    .idex_store_sel(idex_store_sel),
    .idex_of_w_disen(idex_of_w_disen),
    .idex_cp0_dest_addr(idex_cp0_dest_addr),
    .idex_cp0_w_en(idex_cp0_w_en),
    .idex_syscall(idex_syscall),
    .idex_eret(idex_eret),
    .id_imm_ext(id_imm_ext),
    .id_jr(id_jr),
    .id_jump(id_jump),
    .id_rd_addr_sel(id_rd_addr_sel),
    .id_rt_addr_sel(id_rt_addr_sel),
    .id_rt_data_sel(id_rt_data_sel),
    .id_cp0_src_addr(id_cp0_src_addr),
    .idex_exres_sel(idex_exres_sel),
    .idex_movn(idex_movn),
    .idex_movz(idex_movz)
);

// $0 selector
always @(*) begin
    case (id_rt_addr_sel)
    1'b0: id_rt_addr = ifid_rt_addr;
    1'b1: id_rt_addr = 5'd0;
    endcase
end

////////////////////////////////////////////////////////////////////////////
//  GPR
////////////////////////////////////////////////////////////////////////////

GPR gpr (
    .clk(~clk),  // write in the wb cycle, not the next cycle
    .reset(reset),
    .write(wb_reg_w),
    .Rs_addr(ifid_rs_addr),
    .Rt_addr(id_rt_addr),
    .Rd_addr(wb_rd_addr),
    .Rd_in(wb_data_in),
    .Rd_Byte_w_en(wb_reg_byte_w_en),
    .Rs_out(id_rs_out),
    .Rt_out(id_rt_out)
);

extension ext (
    .ifid_imm(ifid_imm),
    .id_imm_ext(id_imm_ext),
    .imm_ext(imm_ext)
);

// Rd addr selector
always @(*) begin
    case (id_rd_addr_sel)
    2'd0: id_rd_addr = ifid_rt_addr;
    2'd1: id_rd_addr = ifid_rd_addr;
    2'd2: id_rd_addr = 5'b11111;
    default: id_rd_addr = 5'b00000;
    endcase
end

// Rt data selector
always @(*) begin
    case (id_rt_data_sel)
    1'b0: id_gpr_rt = cp0_data;
    1'b1: id_gpr_rt = id_rt_out;
    endcase
end

wire ex_nop;  // Indicate that the current instr in EX is nop
wire ex_jmp;  // Transfer jmp to ex -> mem to indicate CU

idex_reg idex_reg (
    // Input
    .clk(clk),
    .reset(reset),
    .id_nop(id_nop),
    .id_jmp(id_jump),
    .id_jr(id_jr),
    .cu_stall(cu_idex_stall),
    .cu_flush(cu_idex_flush),
    .id_rd_addr(id_rd_addr),
    .idex_mem_r_in(idex_mem_r),
    .idex_mem_w_in(idex_mem_w),
    .idex_reg_w_in(idex_reg_w),
    .idex_branch_in(idex_branch),
    .idex_condition_in(idex_condition),
    .idex_of_w_disen_in(idex_of_w_disen),
    .idex_exres_sel_in(idex_exres_sel),
    .idex_B_sel_in(idex_B_sel),
    .idex_ALU_op_in(idex_ALU_op),
    .idex_shamt_sel_in(idex_shamt_sel),
    .idex_shamt_in(idex_shamt),
    .idex_shift_op_in(idex_shift_op),
    .idex_imm_ext_in(imm_ext),
    .idex_rd_addr_in(id_rd_addr),
    .idex_pc_in(ifid_pc),
    .idex_pc_4_in(ifid_pc_4),
    .idex_load_sel_in(idex_load_sel),
    .idex_store_sel_in(idex_store_sel),
    .idex_op_A_in(id_gpr_rs),
    .idex_op_B_in(id_gpr_rt),
    .idex_rs_addr_in(ifid_rs_addr),
    .idex_rt_addr_in(id_rt_addr),
    .idex_cp0_dst_addr_in(ifid_rd_addr),
    .idex_cp0_w_en_in(idex_cp0_w_en),
    .idex_syscall_in(idex_syscall),
    .idex_eret_in(idex_eret),
    .id_movz(idex_movz),
    .id_movn(idex_movn),
    // Output
    .ex_nop(ex_nop),
    .ex_jmp(ex_jmp),
    .ex_jr(ex_jr),
    .idex_mem_w(ex_mem_w),
    .idex_mem_r(ex_mem_r),
    .idex_reg_w(ex_reg_w),
    .idex_branch(ex_branch),
    .idex_condition(ex_condition),
    .idex_of_w_disen(ex_of_w_disen),
    .idex_exres_sel(ex_exres_sel),
    .idex_B_sel(ex_B_sel),
    .idex_ALU_op(ex_ALU_op),
    .idex_shamt_sel(ex_shamt_sel),
    .idex_shamt(ex_shamt),
    .idex_shift_op(ex_shift_op),
    .idex_imm_ext(ex_imm_ext),
    .idex_rd_addr(ex_rd_addr),
    .idex_pc(ex_pc),
    .idex_pc_4(ex_pc_4),
    .idex_load_sel(ex_load_sel),
    .idex_store_sel(ex_store_sel),
    .idex_op_A(ex_op_A),
    .idex_op_B(ex_op_B),
    .idex_rs_addr(ex_rs_addr),
    .idex_rt_addr(ex_rt_addr),
    .idex_cp0_dst_addr(ex_cp0_dst_addr),
    .idex_movz(ex_movz),
    .idex_movn(ex_movn),
    .idex_cp0_w_en(ex_cp0_w_en),
    .idex_syscall(ex_syscall),
    .idex_eret(ex_eret)
);

////////////////////////////////////////////////////////////////////////////
//
//  EX
//
////////////////////////////////////////////////////////////////////////////

// If the instruction is movn or movz, this operand should be 0
// in order to perform the moving operation.
always @(*) begin
    case (ex_movz || ex_movn)
    1'b0: operand_A_after_selection = operand_A_after_forwarding;
    1'b1: operand_A_after_selection = `DATA_WIDTH'd0;
    endcase;
end

// If the instruction is branch or lui, this operand should be immediate.
always @(*) begin
    case (ex_B_sel)
    1'b0: operand_B_after_selection = operand_B_after_forwarding;
    1'b1: operand_B_after_selection = ex_imm_ext;
    endcase
end

// Select the source of the shift amount, from instruction or register.
always @(*) begin
    case (ex_shamt_sel)
    1'b0: shamt_after_sel = ex_shamt;
    1'b1: shamt_after_sel = operand_A_after_forwarding[4:0];
    endcase
end

// Forwarding
always @(*) begin
    case (A_sel)
    2'd0: operand_A_after_forwarding = ex_op_A;
    2'd1: operand_A_after_forwarding = mem_alu_res;
    2'd2: operand_A_after_forwarding = input_A;
    2'd3: operand_A_after_forwarding = 32'dx;
    endcase
end

always @(*) begin
    case (B_sel)
    2'd0: operand_B_after_forwarding = ex_op_B;
    2'd1: operand_B_after_forwarding = mem_alu_res;
    2'd2: operand_B_after_forwarding = input_B;
    2'd3: operand_B_after_forwarding = 32'dx;
    endcase
end

// Exec result selection
always @(*) begin
    case (ex_exres_sel)
    2'd0: exec_result = alu_out;
    2'd1: exec_result = shifter_out;
    2'd2: exec_result = branch_addr;
    2'd3: exec_result = operand_A_after_forwarding;
    default: exec_result = 32'dx;
    endcase
end

alu alu (
    // Input
    .A(operand_A_after_selection),
    .B(operand_B_after_selection),
    .op(ex_ALU_op),
    // Output
    .LF_out(ex_less),
    .OF_out(ex_overflow),
    .ZF_out(ex_zero),
    .alu_out(alu_out)
);

barrel_shifter shifter (
    // Input
    .Shift_in(operand_B_after_forwarding),
    .Shift_amount(shamt_after_sel),
    .Shift_op(ex_shift_op),
    // Output
    .Shift_out(shifter_out)
);

wire ex_reg_w_gened;  // The handled reg_w, often disenable for special cases

reg_w_gen reg_w_gen (
    // Input
    .of(ex_overflow),
    .zf(ex_zero),
    .idex_movz(ex_movz),
    .idex_movnz(ex_movn),
    .idex_reg_w(ex_reg_w),
    .idex_of_w_disen(ex_of_w_disen),
    // Output
    .new_reg_w(ex_reg_w_gened)
);

// Special load and store byte write enable
load_b_w_e_gen inst_load_b_w_e_gen (
    .addr(alu_out[1:0]),
    .load_sel(ex_load_sel),
    .b_w_en(ex_reg_byte_w_en)
);

store_b_w_e_gen  inst_store_b_w_e_gen (
    .addr      ( alu_out[1:0] ),
    .store_sel ( ex_store_sel ),
    .b_w_en    ( ex_mem_byte_w_en )
);

store_shifter  inst_store_shifter (
    .addr         ( alu_out[1:0] ),
    .store_sel    ( ex_store_sel ),
    .rt_data      ( operand_B_after_forwarding ),
    .real_rt_data ( ex_aligned_rt_data )
);

// Forwarding Unit

ForwardUnit FU (
    // Input from EX
    .rs_data       ( ex_op_A ),
    .rt_data       ( ex_op_B ),
    .rs_addr       ( ex_rs_addr ),
    .rt_addr       ( ex_rt_addr ),
    // Input from MEM
    .exmem_rd_addr ( mem_rd_addr ),
    .exmem_byte_en ( mem_reg_byte_w_en ),
    .exmem_w_en    ( mem_reg_w ),
    // Input from WB
    .memwb_data    ( memwb_data ),
    .memwb_rd_addr ( wb_rd_addr ),
    .memwb_byte_en ( wb_reg_byte_w_en ),
    .memwb_w_en    ( wb_reg_w ),
    // Output
    .input_A       ( input_A ),
    .input_B       ( input_B ),
    .A_sel         ( A_sel ),
    .B_sel         ( B_sel )
);


wire mem_nop;  // Indicate that the current instr in MEM is a nop.
wire mem_jmp;  // Transfer the jmp to mem to indicate CU

exmem_reg  inst_exmem_reg (
    // Input from global
    .clk                ( clk ),
    .reset              ( reset ),
    // Input from Control Unit
    .cu_stall           ( cu_exmem_stall ),
    .cu_flush           ( cu_exmem_flush ),
    // Input from EX
    .ex_nop             ( ex_nop ),
    .ex_jmp             ( ex_jmp ),
    .idex_mem_w         ( ex_mem_w ),
    .idex_mem_r         ( ex_mem_r ),
    .idex_reg_w         ( ex_reg_w_gened ),
    .idex_branch        ( ex_branch ),
    .idex_condition     ( ex_condition ),
    .addr_target        ( branch_addr ),
    .alu_lf             ( ex_less ),
    .alu_zf             ( ex_zero ),
    .alu_of             ( ex_overflow ),
    .ex_res             ( exec_result ),
    .real_rd_addr       ( ex_rd_addr ),
    .idex_load_sel      ( ex_load_sel ),
    .idex_store_sel     ( ex_store_sel ),
    .reg_byte_w_en_in   ( ex_reg_byte_w_en ),
    .mem_byte_w_en_in   ( ex_mem_byte_w_en ),
    .idex_pc            ( ex_pc ),
    .idex_pc_4          ( ex_pc_4 ),
    .aligned_rt_data    ( ex_aligned_rt_data ),
    .idex_cp0_dst_addr  ( ex_cp0_dst_addr ),
    .cp0_w_en_in        ( ex_cp0_w_en ),
    .syscall_in         ( ex_syscall ),
    .idex_eret          ( ex_eret ),
    // Output to MEM
    .mem_nop            ( mem_nop ),
    .mem_jmp            ( mem_jmp ),
    .exmem_pc           ( mem_pc ),
    .exmem_pc_4         ( mem_pc_4 ),
    .exmem_mem_w        ( mem_mem_w ),
    .exmem_mem_r        ( mem_mem_r ),
    .exmem_reg_w        ( mem_reg_w ),
    .reg_byte_w_en_out  ( mem_reg_byte_w_en ),
    .exmem_rd_addr      ( mem_rd_addr ),
    .mem_byte_w_en_out  ( mem_mem_byte_w_en ),
    .exmem_alu_res      ( mem_alu_res ),
    .exmem_aligned_rt_data ( mem_aligned_rt_data ),
    .exmem_branch       ( mem_branch ),
    .exmem_condition    ( mem_condition ),
    .exmem_target       ( mem_target ),
    .exmem_lf           ( mem_lf ),
    .exmem_zf           ( mem_zf ),
    .exmem_load_sel     ( mem_load_sel ),
    .exmem_store_sel    ( mem_store_sel ),
    .exmem_cp0_dst_addr ( mem_cp0_dst_addr ),
    .cp0_w_en_out       ( mem_cp0_w_en ),
    .syscall_out        ( mem_syscall ),
    .exmem_eret         ( mem_eret )
);

////////////////////////////////////////////////////////////////////////////////
//
//  MEM
//
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
//  Data Memory
//  Just wire here, see cpu_interface below.
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
//  Branch unit
////////////////////////////////////////////////////////////////////////////////

final_target  inst_final_target (
    .Exmem_branch    ( mem_branch ),
    .Exmem_condition ( mem_condition ),
    .Exmem_target    ( mem_target ),
    .Exmem_pc_4      ( mem_pc_4 ),
    .Exmem_lf        ( mem_lf ),
    .Exmem_zf        ( mem_zf ),
    .Final_target    ( mem_final_target )
);

////////////////////////////////////////////////////////////////////////////////
//  Load shifter
////////////////////////////////////////////////////////////////////////////////

load_shifter  inst_load_shifter (
   .addr        ( mem_alu_res[1:0] ),
   .load_sel    ( mem_load_sel ),
   .mem_data    ( mem_data ),
   .data_to_reg ( mem_aligned_mem_data )
);

////////////////////////////////////////////////////////////////////////////////
//  MEMWB register
//  Output signals defined in the WB section.
////////////////////////////////////////////////////////////////////////////////

wire [`DATA_BUS] wb_aligned_rt_data;

memwb_reg  inst_memwb_reg (
    // Global input
    .clk                 ( clk ),
    .reset               ( reset ),
    .mem_stall           ( mem_stall ),
    // Input from mem
    .exmem_mem_r         ( mem_mem_r ),
    .exmem_reg_w         ( mem_reg_w ),
    .reg_byte_w_en_in    ( mem_reg_byte_w_en ),
    .exmem_rd_addr       ( mem_rd_addr ),
    .mem_data            ( mem_aligned_mem_data ),
    .ex_data             ( mem_alu_res ),
    .exmem_cp0_dst_addr  ( mem_cp0_dst_addr ),
    .exmem_cp0_w_en      ( mem_cp0_w_en ),
    .aligned_rt_data_in  ( mem_aligned_rt_data ),
    // Output to wb
    .memwb_mem_r         ( wb_mem_r ),
    .memwb_reg_w         ( wb_reg_w ),
    .reg_byte_w_en_out   ( wb_reg_byte_w_en ),
    .memwb_rd_addr       ( wb_rd_addr ),
    .memwb_memdata       ( wb_mem_data ),
    .memwb_exdata        ( wb_ex_data ),
    .memwb_cp0_dst_addr  ( wb_cp0_dst_addr ),
    .memwb_cp0_w_en      ( wb_cp0_w_en ),
    .aligned_rt_data_out ( wb_aligned_rt_data )
);

////////////////////////////////////////////////////////////////////////////////
//
//  WB
//
////////////////////////////////////////////////////////////////////////////////

assign wb_data_in = (wb_mem_r) ? wb_mem_data : wb_ex_data;

////////////////////////////////////////////////////////////////////////////////
//
//  Control Unit
//
////////////////////////////////////////////////////////////////////////////////

wire [4:0] cu_exec_code;
wire [`PC_BUS] cu_epc;

control_unit  inst_control_unit (
    // Input
    .clk               ( clk ),
    .reset             ( reset ),
    .mem_stall         ( mem_stall ),
    .mem_nop           ( mem_nop ),
    .ex_nop            ( ex_nop ),
    .mem_jmp           ( mem_jmp ),
    .ifid_rs_addr      ( ifid_rs_addr ),
    .real_rt_addr      ( id_rt_addr ),
    .idex_rd_addr      ( ex_rd_addr ),
    .idex_mem_read     ( ex_mem_r ),
    .predicted_idex_pc ( ex_pc ),
    .predicted_ifid_pc ( ifid_pc ),
    .target_exmem_pc   ( mem_final_target ),
    .mem_pc            ( mem_pc ),
    .cp0_intr          ( cp0_intr ),
    .id_jump           ( id_jump ),
    .exmem_eret        ( mem_eret ),
    .exmem_syscall     ( mem_syscall ),
    // Output
    .cu_pc_src         ( cu_pc_src ),
    .cu_pc_stall       ( cu_pc_stall ),
    .cu_ifid_stall     ( cu_ifid_stall ),
    .cu_idex_stall     ( cu_idex_stall ),
    .cu_exmem_stall    ( cu_exmem_stall ),
    .cu_ifid_flush     ( cu_ifid_flush ),
    .cu_idex_flush     ( cu_idex_flush ),
    .cu_exmem_flush    ( cu_exmem_flush ),
    .cu_cp0_w_en       ( cu_cp0_w_en ),
    .cu_exec_code      ( cu_exec_code ),
    .cu_epc            ( cu_epc ),
    .cu_vector         ( cu_vector ),
    .bpu_write_en      ( bpu_w_en )
);

////////////////////////////////////////////////////////////////////////////////
//
//  CP0
//
////////////////////////////////////////////////////////////////////////////////

cp0 inst_cp0 (
    .Wb_cp0_w_en     ( wb_cp0_w_en ),
    .Cu_cp0_w_en     ( cu_cp0_w_en ),
    .Epc             ( cu_epc ),
    .Id_cp0_src_addr ( id_cp0_src_addr ),
    .Wb_cp0_dst_addr ( wb_cp0_dst_addr ),
    .Ex_data         ( wb_ex_data ),
    .Cu_exec_code    ( cu_exec_code ),
    .Interrupt       ( intr ),
    .Clk             ( clk ),
    .Cp0_data        ( cp0_data ),
    .Cp0_epc         ( epc ),
    .Cp0_intr        ( cp0_intr )
);

////////////////////////////////////////////////////////////////////////////////
//
//  Memory interface
//
////////////////////////////////////////////////////////////////////////////////

cpu_interface inst_ci (
    .ic_addr(pc_out[31:2]),
    .dc_read_in(mem_mem_r),
    .dc_write_in(mem_mem_w),
    .dc_addr(mem_alu_res[31:2]), //????
    .data_reg(mem_aligned_rt_data),
    .dc_byte_w_en(mem_mem_byte_w_en),
    .clk(clk),
    .rst(reset),
    .ic_data_out(ic_data_out),
    .dc_data_out(mem_data),
    .mem_stall(mem_stall)
);

assign mem_pc_out = mem_pc;

endmodule
