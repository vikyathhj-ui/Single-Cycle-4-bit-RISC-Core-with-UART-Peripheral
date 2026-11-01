// pg_gray: prefix "gray" cell. Same as pg_black but produces G only.
// Used where the combined group reaches bit 0: G is then the final carry and
// the group propagate is never needed again.
module pg_gray (
    input  logic gh,
    input  logic ph,
    input  logic gl,
    output logic g
);
    assign g = gh | (ph & gl);
endmodule
