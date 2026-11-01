// rvfi_wrapper for riscv-formal (ext/riscv-formal, see docs/MICROARCH.md §10).
//
// The core's buses see unconstrained data, as in the riscv-formal examples
// (cores/nerv/wrapper.sv):
//  * I-port: any instruction word every cycle (ibus_rdata is free).
//  * D-port: a response may arrive any number of cycles after the request (dbus_rvalid is free
//    but only counts while a request is outstanding); read data is free.
//  * Interrupt lines are free.
// Bus errors are tied to 0: access faults are not part of the formal model (they are covered by
// simulation, docs/VERIFICATION.md). The Q-Channel is held in Q_RUN (QREQn = 1).
module rvfi_wrapper (
	input         clock,
	input         reset,
	`RVFI_OUTPUTS
);
	(* keep *) `rvformal_rand_reg [31:0] ibus_rdata;
	(* keep *) `rvformal_rand_reg        dbus_rvalid_any;
	(* keep *) `rvformal_rand_reg [31:0] dbus_rdata;
	(* keep *) `rvformal_rand_reg        irq_msip;
	(* keep *) `rvformal_rand_reg        irq_mtip;
	(* keep *) `rvformal_rand_reg        irq_meip;

	(* keep *) wire [31:0] ibus_addr;
	(* keep *) wire        dbus_req;
	(* keep *) wire        dbus_we;
	(* keep *) wire [31:0] dbus_addr;
	(* keep *) wire [ 3:0] dbus_be;
	(* keep *) wire [31:0] dbus_wdata;
	(* keep *) wire        qaccept_n, qdeny, qactive, core_idle, irq_wake;

	// One request outstanding at most; the response comes in a later cycle.
	reg outstanding;
	always @(posedge clock) begin
		if (reset)            outstanding <= 1'b0;
		else if (dbus_req)    outstanding <= 1'b1;
		else if (dbus_rvalid) outstanding <= 1'b0;
	end
	wire dbus_rvalid = dbus_rvalid_any && outstanding;

	lp_rv32_core uut (
		.clk        (clock),
		.rst_n      (!reset),
		.ibus_addr  (ibus_addr),
		.ibus_rdata (ibus_rdata),
		.ibus_err   (1'b0),
		.dbus_req   (dbus_req),
		.dbus_we    (dbus_we),
		.dbus_addr  (dbus_addr),
		.dbus_be    (dbus_be),
		.dbus_wdata (dbus_wdata),
		.dbus_rvalid(dbus_rvalid),
		.dbus_rdata (dbus_rdata),
		.dbus_err   (1'b0),
		.irq_msip   (irq_msip),
		.irq_mtip   (irq_mtip),
		.irq_meip   (irq_meip),
		.qreq_n     (1'b1),
		.qaccept_n  (qaccept_n),
		.qdeny      (qdeny),
		.qactive    (qactive),
		.core_idle  (core_idle),
		.irq_wake   (irq_wake),
		`RVFI_CONN32
	);

`ifdef LP_FAIRNESS
	// Liveness only: the bus answers within 2 cycles, and the instruction stream contains no WFI
	// (WFI waits for an interrupt by design, SPEC §5.5, so it may legally never retire).
	reg [1:0] waiting;
	always @(posedge clock) begin
		if (reset || !outstanding || dbus_rvalid) waiting <= 0;
		else                                      waiting <= waiting + 1;
		assume (waiting < 2);
		assume (ibus_rdata != 32'h1050_0073);
	end
`endif
endmodule
