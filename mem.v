module mem_model #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 32,
    parameter LATENCY    = 3
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   mem_rd,
    input  wire                   mem_wr,
    input  wire [ADDR_WIDTH-1:0]  mem_addr,
    input  wire [DATA_WIDTH-1:0]  mem_wdata,
    output reg  [DATA_WIDTH-1:0]  mem_rdata,
    output reg                    mem_ready
);

    reg [DATA_WIDTH-1:0] mem_array [0:(1<<ADDR_WIDTH)-1];
    integer i;
    initial begin

        for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1)
            mem_array[i] = i + 32'hA000_0000;
    end

    reg [$clog2(LATENCY+1)-1:0] cnt;
    reg busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt       <= 0;
            busy      <= 1'b0;
            mem_ready <= 1'b0;
            mem_rdata <= {DATA_WIDTH{1'b0}};
        end else begin
            mem_ready <= 1'b0;
            if (!busy) begin
                if (mem_rd || mem_wr) begin
                    busy <= 1'b1;
                    cnt  <= 1;
                end
            end else begin
                if (cnt == LATENCY-1) begin
                    if (mem_wr)
                        mem_array[mem_addr] <= mem_wdata;
                    else
                        mem_rdata <= mem_array[mem_addr];
                    mem_ready <= 1'b1;
                    busy      <= 1'b0;
                    cnt       <= 0;
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end
        end
    end

endmodule
