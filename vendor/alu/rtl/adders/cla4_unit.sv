// cla4_unit: 4-bit carry-lookahead unit.
// From four (g, p) pairs and a carry-in, computes the carries into positions
// 1..3 in parallel (no ripple) plus the group generate/propagate, so units can
// be stacked into a lookahead tree (adder_cla4).
module cla4_unit (
    input  logic [3:0] g,
    input  logic [3:0] p,
    input  logic       c0,
    output logic [3:1] c,
    output logic       gg,
    output logic       gp
);
    assign c[1] = g[0] | (p[0] & c0);
    assign c[2] = g[1] | (p[1] & g[0]) | (p[1] & p[0] & c0);
    assign c[3] = g[2] | (p[2] & g[1]) | (p[2] & p[1] & g[0]) | (p[2] & p[1] & p[0] & c0);
    assign gg   = g[3] | (p[3] & g[2]) | (p[3] & p[2] & g[1]) | (p[3] & p[2] & p[1] & g[0]);
    assign gp   = &p;
endmodule
