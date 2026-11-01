// pg_black: prefix "black" cell (the dot operator on generate/propagate pairs).
// Combines a high group (gh, ph) with the adjacent lower group (gl, pl):
//   G = gh | ph & gl,  P = ph & pl
// Used where the combined group does not yet reach bit 0, so P is still needed.
module pg_black (
    input  logic gh,
    input  logic ph,
    input  logic gl,
    input  logic pl,
    output logic g,
    output logic p
);
    assign g = gh | (ph & gl);
    assign p = ph & pl;
endmodule
