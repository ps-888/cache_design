module cache_top #(
    parameter ADDR_WIDTH   = 12,
    parameter DATA_WIDTH   = 32,
    parameter SETS         = 32,
    parameter WAYS         = 2,
    parameter BLOCK_WORDS  = 4
) (
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire                     cpu_req,
    input  wire                     cpu_we,
    input  wire [ADDR_WIDTH-1:0]    cpu_addr,
    input  wire [DATA_WIDTH-1:0]    cpu_wdata,
    output reg  [DATA_WIDTH-1:0]    cpu_rdata,
    output reg                      cpu_ready,
    output reg                      cpu_hit,

    output reg                      mem_rd,
    output reg                      mem_wr,
    output reg  [ADDR_WIDTH-1:0]    mem_addr,
    output reg  [DATA_WIDTH-1:0]    mem_wdata,
    input  wire [DATA_WIDTH-1:0]    mem_rdata,
    input  wire                     mem_ready
);

    localparam INDEX_WIDTH  = $clog2(SETS);
    localparam OFFSET_WIDTH = $clog2(BLOCK_WORDS);
    localparam TAG_WIDTH    = ADDR_WIDTH - INDEX_WIDTH - OFFSET_WIDTH;

    reg [DATA_WIDTH-1:0] data_mem  [0:WAYS-1][0:SETS-1][0:BLOCK_WORDS-1];
    reg [TAG_WIDTH-1:0]  tag_mem   [0:WAYS-1][0:SETS-1];
    reg                  valid_mem [0:WAYS-1][0:SETS-1];
    reg                  dirty_mem [0:WAYS-1][0:SETS-1];
    reg                  lru_mem   [0:SETS-1];

    integer w, s, b;
    initial begin
        for (w = 0; w < WAYS; w = w + 1)
            for (s = 0; s < SETS; s = s + 1) begin
                valid_mem[w][s] = 1'b0;
                dirty_mem[w][s] = 1'b0;
                tag_mem[w][s]   = {TAG_WIDTH{1'b0}};
                for (b = 0; b < BLOCK_WORDS; b = b + 1)
                    data_mem[w][s][b] = {DATA_WIDTH{1'b0}};
            end
        for (s = 0; s < SETS; s = s + 1)
            lru_mem[s] = 1'b0;
    end

    localparam S_IDLE      = 4'd0,
               S_COMPARE   = 4'd1,
               S_WRITEBACK = 4'd2,
               S_REFILL    = 4'd3,
               S_DONE      = 4'd4;

    reg [3:0] state, next_state;

    reg                   r_we;
    reg [ADDR_WIDTH-1:0]  r_addr;
    reg [DATA_WIDTH-1:0]  r_wdata;

    wire [OFFSET_WIDTH-1:0] r_off   = r_addr[OFFSET_WIDTH-1:0];
    wire [INDEX_WIDTH-1:0]  r_index = r_addr[OFFSET_WIDTH+INDEX_WIDTH-1:OFFSET_WIDTH];
    wire [TAG_WIDTH-1:0]    r_tag   = r_addr[ADDR_WIDTH-1:OFFSET_WIDTH+INDEX_WIDTH];

    wire hit0 = valid_mem[0][r_index] && (tag_mem[0][r_index] == r_tag);
    wire hit1 = valid_mem[1][r_index] && (tag_mem[1][r_index] == r_tag);
    wire hit  = hit0 | hit1;
    wire hit_way = hit0 ? 1'b0 : 1'b1;

    reg victim_way;
    reg [OFFSET_WIDTH-1:0] word_cnt;
    reg refill_done;

    always @* begin

        victim_way = lru_mem[r_index];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            cpu_ready <= 1'b0;
            cpu_hit   <= 1'b0;
            mem_rd    <= 1'b0;
            mem_wr    <= 1'b0;
            word_cnt  <= {OFFSET_WIDTH{1'b0}};
            refill_done <= 1'b0;
            r_we      <= 1'b0;
            r_addr    <= {ADDR_WIDTH{1'b0}};
            r_wdata   <= {DATA_WIDTH{1'b0}};
        end else begin
            cpu_ready <= 1'b0;
            mem_rd    <= 1'b0;
            mem_wr    <= 1'b0;

            case (state)

                S_IDLE: begin
                    if (cpu_req) begin
                        r_we        <= cpu_we;
                        r_addr      <= cpu_addr;
                        r_wdata     <= cpu_wdata;
                        refill_done <= 1'b0;
                        state       <= S_COMPARE;
                    end
                end

                S_COMPARE: begin
                    if (hit) begin
                        if (!refill_done)
                            cpu_hit <= 1'b1;
                        if (r_we) begin
                            data_mem[hit_way][r_index][r_off] <= r_wdata;
                            dirty_mem[hit_way][r_index]       <= 1'b1;
                            cpu_rdata <= r_wdata;
                        end else begin
                            cpu_rdata <= data_mem[hit_way][r_index][r_off];
                        end

                        lru_mem[r_index] <= ~hit_way;
                        cpu_ready <= 1'b1;
                        state     <= S_DONE;
                    end else begin
                        cpu_hit  <= 1'b0;
                        word_cnt <= {OFFSET_WIDTH{1'b0}};
                        if (dirty_mem[victim_way][r_index])
                            state <= S_WRITEBACK;
                        else
                            state <= S_REFILL;
                    end
                end

                S_WRITEBACK: begin
                    mem_wr    <= 1'b1;
                    mem_addr  <= {tag_mem[victim_way][r_index], r_index, word_cnt};
                    mem_wdata <= data_mem[victim_way][r_index][word_cnt];
                    if (mem_ready) begin
                        if (word_cnt == BLOCK_WORDS-1) begin
                            word_cnt <= {OFFSET_WIDTH{1'b0}};
                            state    <= S_REFILL;
                        end else begin
                            word_cnt <= word_cnt + 1'b1;
                        end
                    end
                end

                S_REFILL: begin
                    mem_rd   <= 1'b1;
                    mem_addr <= {r_tag, r_index, word_cnt};
                    if (mem_ready) begin
                        data_mem[victim_way][r_index][word_cnt] <= mem_rdata;
                        if (word_cnt == BLOCK_WORDS-1) begin
                            tag_mem[victim_way][r_index]   <= r_tag;
                            valid_mem[victim_way][r_index] <= 1'b1;
                            dirty_mem[victim_way][r_index] <= 1'b0;
                            refill_done <= 1'b1;
                            state <= S_COMPARE;
                        end else begin
                            word_cnt <= word_cnt + 1'b1;
                        end
                    end
                end

                S_DONE: begin
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
