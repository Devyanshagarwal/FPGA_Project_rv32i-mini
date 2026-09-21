// -----------------------------------------------------------------------------
// tb_rv32i.v — Testbench for rv32i_core
// Runs the embedded sum(1..10) program, prints a per-cycle trace, then
// checks that dmem[0] == 55.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_rv32i;
    reg         clk;
    reg         rst_n;
    wire [31:0] pc, instr, x1, x2, x3;

    rv32i_core cpu (
        .clk       (clk),
        .rst_n     (rst_n),
        .pc_out    (pc),
        .instr_out (instr),
        .reg_x1    (x1),
        .reg_x2    (x2),
        .reg_x3    (x3)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    integer cycle;
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_rv32i);

        rst_n = 0;
        cycle = 0;
        #12 rst_n = 1;  // release reset after one full cycle

        $display("cyc | PC   | instr    | x1(sum) x2(i) x3(lim)");
        $display("----+------+----------+-----------------------");

        repeat (60) begin
            @(posedge clk);
            #1;
            $display("%3d | %4h | %h |  %3d     %3d    %3d",
                     cycle, pc, instr, x1, x2, x3);
            cycle = cycle + 1;
        end

        $display("");
        $display("Final x1 (sum)   = %0d  (expected 55)", x1);
        $display("dmem[0]          = %0d  (expected 55)", cpu.dmem[0]);
        if (x1 == 32'd55 && cpu.dmem[0] == 32'd55)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end
endmodule
