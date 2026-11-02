// soc_sys_tb: SoC wrapper for the system tests (tb/system/test_*.py, BRIEF A5 "System tests").
//
// * clk: generated in this wrapper (10 ns period).
// * +imem=<hex>: preload IMEM (one 32-bit word per line) before reset is released.
// * Power-aware corruption model (behavioural, as in P2; BRIEF A6 "behavioural power gating"):
//   when the main power switch of a domain turns off (PMU psw_main_ack falls), the state that a
//   real power-off would lose is overwritten with random values: CORE -> the register file (its
//   flops have no reset); PERI -> the UART TX/RX FIFO storage. Flops with a reset are already
//   forced by the PMU's domain reset, which stays asserted while the domain is off. MEM (IMEM,
//   DMEM) and AON keep their contents. corrupt_core / corrupt_peri count the events.
// * Clock monitor: clk_core_edges counts rising edges of the gated CORE clock (the test reads it
//   to prove the clock is stopped in IDLE).
// * With RISCV_FORMAL defined and +trace=<file>: one line per retired instruction (CPI study).
`default_nettype none
module soc_sys_tb (
    input  logic        rst_n,
    input  logic        boot_sel,
    input  logic        uart_rxd,
    output logic        uart_txd,
    input  logic [7:0]  gpio_i,
    output logic [7:0]  gpio_o,
    output logic [7:0]  gpio_oe,
    output logic [31:0] corrupt_core,
    output logic [31:0] corrupt_peri,
    output logic [31:0] clk_core_edges
);
    // 100 MHz simulation clock generated here (not by cocotb) for simulation speed. Cycle counts are
    // what the tests report; the clock period has no meaning for the design.
    logic clk = 1'b0;
    always #5 clk = ~clk;

    lp_rv32_soc u_soc (.clk(clk), .rst_n(rst_n), .boot_sel(boot_sel), .uart_rxd(uart_rxd),
                       .uart_txd(uart_txd), .gpio_i(gpio_i), .gpio_o(gpio_o), .gpio_oe(gpio_oe));

    string f;
    initial begin
        corrupt_core = 0;
        corrupt_peri = 0;
        clk_core_edges = 0;
        if ($value$plusargs("imem=%s", f)) $readmemh(f, u_soc.u_imem.mem);
    end

    // ---------------------------------------------------------------- corruption model
    logic main0_q, main2_q;
    always @(posedge clk) begin
        main0_q <= u_soc.psw_main_ack[0];
        main2_q <= u_soc.psw_main_ack[2];
        if (main0_q && !u_soc.psw_main_ack[0]) begin
            for (int r = 1; r < 32; r++) u_soc.u_core.u_rf.regs[r] = $urandom;
            corrupt_core = corrupt_core + 1;
        end
        if (main2_q && !u_soc.psw_main_ack[2]) begin
            for (int i = 0; i < 16; i++) begin
                u_soc.u_uart.txf[i] = 8'($urandom);
                u_soc.u_uart.rxf[i] = 8'($urandom);
            end
            corrupt_peri = corrupt_peri + 1;
        end
    end

    always @(posedge u_soc.clk_core) clk_core_edges = clk_core_edges + 1;

`ifdef RISCV_FORMAL
    // ---------------------------------------------------------------- retire trace
    int fd = 0;
    longint cyc = 0;
    initial if ($value$plusargs("trace=%s", f)) fd = $fopen(f, "w");
    always @(posedge clk) begin
        cyc <= cyc + 1;
        if (fd != 0 && u_soc.u_core.rvfi_valid)
            $fwrite(fd, "%0d %08x %08x %0d %0d %0d %0d %0d\n", cyc, u_soc.u_core.rvfi_pc_rdata,
                    u_soc.u_core.rvfi_insn, u_soc.u_core.rvfi_trap, u_soc.u_core.rvfi_intr,
                    u_soc.u_core.rvfi_rd_addr, u_soc.u_core.rvfi_rs1_addr, u_soc.u_core.rvfi_rs2_addr);
    end
    final if (fd != 0) $fclose(fd);

    // ---------------------------------------------------------------- hazard statistics (CPI study)
    // Counted from the RVFI retire stream, in program order (docs/MICROARCH.md §9):
    //  st_ret      retired instructions (traps included)
    //  st_first/st_last  cycle of the first / last retirement (cycles = last - first)
    //  st_ct       control transfers that changed the pc (taken branch, jump, trap, MRET, interrupt)
    //  st_load     loads
    //  st_lu1      instruction reading a register a load wrote one instruction earlier
    //  st_lu2      ... two instructions earlier (and not one earlier)
    // st_reset clears all counters (driven by the test before the region of interest).
    longint st_ret = 0, st_first = 0, st_last = 0, st_ct = 0, st_load = 0, st_lu1 = 0, st_lu2 = 0;
    bit     st_reset = 0;
    logic [31:0] exp_pc = 0;
    logic [4:0]  ld1 = 0, ld2 = 0;        // rd of a load 1 / 2 retirements ago (0 = none)
    always @(posedge clk) begin
        if (st_reset) begin
            st_ret <= 0; st_ct <= 0; st_load <= 0; st_lu1 <= 0; st_lu2 <= 0; st_first <= 0;
        end else if (u_soc.u_core.rvfi_valid) begin
            logic [4:0] r1, r2;
            logic       dep1, dep2, is_ld;
            r1 = u_soc.u_core.rvfi_rs1_addr;
            r2 = u_soc.u_core.rvfi_rs2_addr;
            dep1 = ld1 != 0 && (r1 == ld1 || r2 == ld1);
            dep2 = !dep1 && ld2 != 0 && (r1 == ld2 || r2 == ld2);
            is_ld = u_soc.u_core.rvfi_mem_rmask != 0;
            if (st_ret == 0) st_first <= cyc;
            st_last <= cyc;
            st_ret  <= st_ret + 1;
            if (st_ret != 0 && u_soc.u_core.rvfi_pc_rdata != exp_pc) st_ct <= st_ct + 1;
            if (is_ld) st_load <= st_load + 1;
            if (dep1) st_lu1 <= st_lu1 + 1;
            if (dep2) st_lu2 <= st_lu2 + 1;
            exp_pc = u_soc.u_core.rvfi_pc_rdata + 4;
            ld2 <= ld1;
            ld1 <= (is_ld && !u_soc.u_core.rvfi_trap) ? u_soc.u_core.rvfi_rd_addr : 5'd0;
        end
    end
`endif
endmodule
`default_nettype wire
