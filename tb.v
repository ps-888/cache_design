`timescale 1ns/1ps

module cache_tb;

    localparam ADDR_WIDTH  = 12;
    localparam DATA_WIDTH  = 32;
    localparam SETS        = 32;
    localparam WAYS        = 2;
    localparam BLOCK_WORDS = 4;

    reg                    clk;
    reg                    rst_n;
    reg                    cpu_req;
    reg                    cpu_we;
    reg  [ADDR_WIDTH-1:0]  cpu_addr;
    reg  [DATA_WIDTH-1:0]  cpu_wdata;
    wire [DATA_WIDTH-1:0]  cpu_rdata;
    wire                   cpu_ready;
    wire                   cpu_hit;

    wire                   mem_rd, mem_wr;
    wire [ADDR_WIDTH-1:0]  mem_addr;
    wire [DATA_WIDTH-1:0]  mem_wdata;
    wire [DATA_WIDTH-1:0]  mem_rdata;
    wire                   mem_ready;

    integer pass_count = 0;
    integer fail_count = 0;

    cache_top #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .SETS(SETS), .WAYS(WAYS), .BLOCK_WORDS(BLOCK_WORDS)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata), .cpu_rdata(cpu_rdata),
        .cpu_ready(cpu_ready), .cpu_hit(cpu_hit),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ready(mem_ready)
    );

    mem_model #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .LATENCY(3)
    ) mem (
        .clk(clk), .rst_n(rst_n),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ready(mem_ready)
    );

    always #5 clk = ~clk;

    function [ADDR_WIDTH-1:0] mk_addr;
        input [4:0] tag;
        input [4:0] index;
        input [1:0] offset;
        begin
            mk_addr = {tag, index, offset};
        end
    endfunction

    task do_reset;
        begin
            clk = 0; rst_n = 0; cpu_req = 0; cpu_we = 0;
            cpu_addr = 0; cpu_wdata = 0;
            repeat (4) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    task cpu_op;
        input                   we;
        input [ADDR_WIDTH-1:0]  addr;
        input [DATA_WIDTH-1:0]  wdata;
        output [DATA_WIDTH-1:0] rdata;
        output                  was_hit;
        begin
            @(negedge clk);
            cpu_req   = 1'b1;
            cpu_we    = we;
            cpu_addr  = addr;
            cpu_wdata = wdata;
            @(negedge clk);
            cpu_req   = 1'b0;

            while (!cpu_ready) @(negedge clk);
            rdata   = cpu_rdata;
            was_hit = cpu_hit;
        end
    endtask

    task check_hit;
        input               expect_hit;
        input                actual_hit;
        input [255:0]        label;
        begin
            if (actual_hit === expect_hit) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s : expected %s, got %s",
                          label, expect_hit ? "HIT" : "MISS", actual_hit ? "HIT" : "MISS");
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s : expected %s, got %s",
                          label, expect_hit ? "HIT" : "MISS", actual_hit ? "HIT" : "MISS");
            end
        end
    endtask

    task check_data;
        input [DATA_WIDTH-1:0] expected;
        input [DATA_WIDTH-1:0] actual;
        input [255:0]          label;
        begin
            if (expected === actual) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s : data = 0x%08h", label, actual);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s : expected 0x%08h, got 0x%08h", label, expected, actual);
            end
        end
    endtask

    reg [DATA_WIDTH-1:0] rd;
    reg                  hit;
    reg [ADDR_WIDTH-1:0] addrA, addrB, addrC;

    initial begin
        $dumpfile("cache_tb.vcd");
        $dumpvars(0, cache_tb);

        do_reset;

        addrA = mk_addr(5'd1, 5'd3, 2'd0);
        addrB = mk_addr(5'd2, 5'd3, 2'd0);
        addrC = mk_addr(5'd3, 5'd3, 2'd0);

        cpu_op(1'b0, addrA, 32'h0, rd, hit);
        check_hit(1'b0, hit, "T1 compulsory miss on A (way0 fill)");

        cpu_op(1'b0, addrA, 32'h0, rd, hit);
        check_hit(1'b1, hit, "T2 hit on A after fill");
        check_data(32'hA000_0000 + (addrA), rd, "T2 data correctness (word0 of A's block)");

        cpu_op(1'b0, addrB, 32'h0, rd, hit);
        check_hit(1'b0, hit, "T3 compulsory miss on B (way1 fill)");

        cpu_op(1'b0, addrB, 32'h0, rd, hit);
        check_hit(1'b1, hit, "T4 hit on B after fill");

        cpu_op(1'b1, addrA, 32'hDEAD_BEEF, rd, hit);
        check_hit(1'b1, hit, "T5 write-hit on A (dirties way0)");

        cpu_op(1'b0, addrC, 32'h0, rd, hit);
        check_hit(1'b0, hit, "T6 conflict miss on C evicts B (clean, no writeback)");

        cpu_op(1'b0, addrB, 32'h0, rd, hit);
        check_hit(1'b0, hit, "T7 conflict miss on B (was evicted by C)");

        cpu_op(1'b0, mk_addr(5'd4, 5'd3, 2'd0), 32'h0, rd, hit);
        check_hit(1'b0, hit, "T8 conflict miss evicts dirty A (triggers writeback)");

        cpu_op(1'b0, addrA, 32'h0, rd, hit);
        check_hit(1'b0, hit, "T9 miss on A after writeback-eviction");
        check_data(32'hDEAD_BEEF, rd, "T9 writeback data integrity check");

        cpu_op(1'b1, mk_addr(5'd7, 5'd10, 2'd0), 32'h1111_0000, rd, hit);
        cpu_op(1'b1, mk_addr(5'd7, 5'd10, 2'd1), 32'h2222_0000, rd, hit);
        cpu_op(1'b1, mk_addr(5'd7, 5'd10, 2'd2), 32'h3333_0000, rd, hit);
        cpu_op(1'b1, mk_addr(5'd7, 5'd10, 2'd3), 32'h4444_0000, rd, hit);
        cpu_op(1'b0, mk_addr(5'd7, 5'd10, 2'd0), 32'h0, rd, hit);
        check_hit(1'b1, hit, "T10a hit, offset0");
        check_data(32'h1111_0000, rd, "T10a offset0 data");
        cpu_op(1'b0, mk_addr(5'd7, 5'd10, 2'd2), 32'h0, rd, hit);
        check_hit(1'b1, hit, "T10b hit, offset2");
        check_data(32'h3333_0000, rd, "T10b offset2 data");

        $display("--------------------------------------------------");
        $display("TEST SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: %0d TEST(S) FAILED", fail_count);
        $display("--------------------------------------------------");

        #20 $finish;
    end

    initial begin
        #20000;
        $display("[FAIL] TIMEOUT - simulation did not complete");
        $finish;
    end

endmodule
