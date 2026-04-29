// IPv4 头校验和计算模块。
// 对 16 位字进行一补和折叠，输出发送 IP 头需要的校验字段。


module ip_checksum(
	input           clk            ,
	input           reset_n        ,

	input           cal_en         ,

	input   [3:0]   IP_ver         ,
	input   [3:0]   IP_hdr_len     ,
	input   [7:0]   IP_tos         ,
	input   [15:0]  IP_total_len   ,
	input   [15:0]  IP_id          ,
	input           IP_rsv         ,
	input           IP_df          ,
	input           IP_mf          ,
	input   [12:0]  IP_frag_offset ,
	input   [7:0]   IP_ttl         ,
	input   [7:0]   IP_protocol    ,
	input   [31:0]  src_ip         ,
	input   [31:0]  dst_ip         ,

	output  [15:0]  checksum

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // reg 信号保存跨周期状态、计数器、握手标志和流水线寄存结果。
	reg  [31:0]suma;

    // wire 信号承载组合逻辑结果或子模块之间的连接。
	wire [16:0]sumb;
	wire [15:0]sumc;

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
	always@(posedge clk or negedge reset_n)
	if(!reset_n)
		suma <= 32'd0;
	else if(cal_en)
		suma <= {IP_ver,IP_hdr_len,IP_tos}+IP_total_len+IP_id+
			{IP_rsv,IP_df,IP_mf,IP_frag_offset}+{IP_ttl,IP_protocol}+
			src_ip[31:16]+src_ip[15:0]+dst_ip[31:16]+dst_ip[15:0];
	else
		suma <= suma;

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
	assign sumb = suma[31:16]+suma[15:0];

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
	assign sumc = sumb[16]+sumb[15:0];

	assign checksum = ~sumc;

endmodule
