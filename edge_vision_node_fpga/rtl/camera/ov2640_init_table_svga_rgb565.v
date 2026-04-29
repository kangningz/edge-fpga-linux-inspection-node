`timescale 1ns / 1ps
// OV2640 SVGA RGB565 初始化寄存器表。
// 表项配置输出尺寸、色彩格式、时序和相关图像参数，最后一项作为结束标志。

module ov2640_init_table_svga_rgb565 (
    input  wire [7:0] index,
    output reg  [7:0] reg_addr,
    output reg  [7:0] reg_data,
    output reg        is_delay,
    output reg [23:0] delay_ms,
    output reg        table_end

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // 组合逻辑：根据当前状态和输入信号计算下一拍控制结果。
    always @(*) begin
        reg_addr  = 8'h00;
        reg_data  = 8'h00;
        is_delay  = 1'b0;
        delay_ms  = 24'd0;
        table_end = 1'b0;

            // 状态机分支：按当前阶段执行握手、计数或数据搬运动作。
        case (index)
            8'd0: begin reg_addr = 8'hFF; reg_data = 8'h01; end
            8'd1: begin reg_addr = 8'h12; reg_data = 8'h80; end
            8'd2: begin is_delay = 1'b1; delay_ms = 24'd10; end
            8'd3: begin reg_addr = 8'hFF; reg_data = 8'h00; end

            8'd4: begin reg_addr = 8'hFF; reg_data = 8'h00; end
            8'd5: begin reg_addr = 8'h2C; reg_data = 8'hFF; end
            8'd6: begin reg_addr = 8'h2E; reg_data = 8'hDF; end
            8'd7: begin reg_addr = 8'hFF; reg_data = 8'h01; end
            8'd8: begin reg_addr = 8'h3C; reg_data = 8'h32; end
            8'd9: begin reg_addr = 8'h11; reg_data = 8'h01; end
            8'd10: begin reg_addr = 8'h09; reg_data = 8'h02; end
            8'd11: begin reg_addr = 8'h04; reg_data = 8'h28; end
            8'd12: begin reg_addr = 8'h13; reg_data = 8'hE5; end
            8'd13: begin reg_addr = 8'h14; reg_data = 8'h48; end
            8'd14: begin reg_addr = 8'h2C; reg_data = 8'h0C; end
            8'd15: begin reg_addr = 8'h33; reg_data = 8'h78; end
            8'd16: begin reg_addr = 8'h3A; reg_data = 8'h33; end
            8'd17: begin reg_addr = 8'h3B; reg_data = 8'hFB; end
            8'd18: begin reg_addr = 8'h3E; reg_data = 8'h00; end
            8'd19: begin reg_addr = 8'h43; reg_data = 8'h11; end
            8'd20: begin reg_addr = 8'h16; reg_data = 8'h10; end
            8'd21: begin reg_addr = 8'h39; reg_data = 8'h92; end
            8'd22: begin reg_addr = 8'h35; reg_data = 8'hDA; end
            8'd23: begin reg_addr = 8'h22; reg_data = 8'h1A; end
            8'd24: begin reg_addr = 8'h37; reg_data = 8'hC3; end
            8'd25: begin reg_addr = 8'h23; reg_data = 8'h00; end
            8'd26: begin reg_addr = 8'h34; reg_data = 8'hC0; end
            8'd27: begin reg_addr = 8'h06; reg_data = 8'h88; end
            8'd28: begin reg_addr = 8'h07; reg_data = 8'hC0; end
            8'd29: begin reg_addr = 8'h0D; reg_data = 8'h87; end
            8'd30: begin reg_addr = 8'h0E; reg_data = 8'h41; end
            8'd31: begin reg_addr = 8'h4C; reg_data = 8'h00; end
            8'd32: begin reg_addr = 8'h4A; reg_data = 8'h81; end
            8'd33: begin reg_addr = 8'h21; reg_data = 8'h99; end
            8'd34: begin reg_addr = 8'h24; reg_data = 8'h40; end
            8'd35: begin reg_addr = 8'h25; reg_data = 8'h38; end
            8'd36: begin reg_addr = 8'h26; reg_data = 8'h82; end
            8'd37: begin reg_addr = 8'h5C; reg_data = 8'h00; end
            8'd38: begin reg_addr = 8'h63; reg_data = 8'h00; end
            8'd39: begin reg_addr = 8'h61; reg_data = 8'h70; end
            8'd40: begin reg_addr = 8'h62; reg_data = 8'h80; end
            8'd41: begin reg_addr = 8'h7C; reg_data = 8'h05; end
            8'd42: begin reg_addr = 8'h20; reg_data = 8'h80; end
            8'd43: begin reg_addr = 8'h28; reg_data = 8'h30; end
            8'd44: begin reg_addr = 8'h6C; reg_data = 8'h00; end
            8'd45: begin reg_addr = 8'h6D; reg_data = 8'h80; end
            8'd46: begin reg_addr = 8'h6E; reg_data = 8'h00; end
            8'd47: begin reg_addr = 8'h70; reg_data = 8'h02; end
            8'd48: begin reg_addr = 8'h71; reg_data = 8'h94; end
            8'd49: begin reg_addr = 8'h73; reg_data = 8'hC1; end
            8'd50: begin reg_addr = 8'h3D; reg_data = 8'h34; end
            8'd51: begin reg_addr = 8'h5A; reg_data = 8'h57; end
            8'd52: begin reg_addr = 8'h4F; reg_data = 8'hBB; end
            8'd53: begin reg_addr = 8'h50; reg_data = 8'h9C; end
            8'd54: begin reg_addr = 8'h12; reg_data = 8'h20; end
            8'd55: begin reg_addr = 8'h17; reg_data = 8'h11; end
            8'd56: begin reg_addr = 8'h18; reg_data = 8'h43; end
            8'd57: begin reg_addr = 8'h19; reg_data = 8'h00; end
            8'd58: begin reg_addr = 8'h1A; reg_data = 8'h25; end
            8'd59: begin reg_addr = 8'h32; reg_data = 8'h89; end
            8'd60: begin reg_addr = 8'h37; reg_data = 8'hC0; end
            8'd61: begin reg_addr = 8'h4F; reg_data = 8'hCA; end
            8'd62: begin reg_addr = 8'h50; reg_data = 8'hA8; end
            8'd63: begin reg_addr = 8'h6D; reg_data = 8'h00; end
            8'd64: begin reg_addr = 8'h3D; reg_data = 8'h38; end
            8'd65: begin reg_addr = 8'hFF; reg_data = 8'h00; end
            8'd66: begin reg_addr = 8'hE5; reg_data = 8'h7F; end
            8'd67: begin reg_addr = 8'hF9; reg_data = 8'hC0; end
            8'd68: begin reg_addr = 8'h41; reg_data = 8'h24; end
            8'd69: begin reg_addr = 8'hE0; reg_data = 8'h14; end
            8'd70: begin reg_addr = 8'h76; reg_data = 8'hFF; end
            8'd71: begin reg_addr = 8'h33; reg_data = 8'hA0; end
            8'd72: begin reg_addr = 8'h42; reg_data = 8'h20; end
            8'd73: begin reg_addr = 8'h43; reg_data = 8'h18; end
            8'd74: begin reg_addr = 8'h4C; reg_data = 8'h00; end
            8'd75: begin reg_addr = 8'h87; reg_data = 8'h50; end
            8'd76: begin reg_addr = 8'h88; reg_data = 8'h3F; end
            8'd77: begin reg_addr = 8'hD7; reg_data = 8'h03; end
            8'd78: begin reg_addr = 8'hD9; reg_data = 8'h10; end
            8'd79: begin reg_addr = 8'hD3; reg_data = 8'h82; end
            8'd80: begin reg_addr = 8'hC8; reg_data = 8'h08; end
            8'd81: begin reg_addr = 8'hC9; reg_data = 8'h80; end
            8'd82: begin reg_addr = 8'h7C; reg_data = 8'h00; end
            8'd83: begin reg_addr = 8'h7D; reg_data = 8'h00; end
            8'd84: begin reg_addr = 8'h7C; reg_data = 8'h03; end
            8'd85: begin reg_addr = 8'h7D; reg_data = 8'h48; end
            8'd86: begin reg_addr = 8'h7D; reg_data = 8'h48; end
            8'd87: begin reg_addr = 8'h7C; reg_data = 8'h08; end
            8'd88: begin reg_addr = 8'h7D; reg_data = 8'h20; end
            8'd89: begin reg_addr = 8'h7D; reg_data = 8'h10; end
            8'd90: begin reg_addr = 8'h7D; reg_data = 8'h0E; end
            8'd91: begin reg_addr = 8'h90; reg_data = 8'h00; end
            8'd92: begin reg_addr = 8'h91; reg_data = 8'h0E; end
            8'd93: begin reg_addr = 8'h91; reg_data = 8'h1A; end
            8'd94: begin reg_addr = 8'h91; reg_data = 8'h31; end
            8'd95: begin reg_addr = 8'h91; reg_data = 8'h5A; end
            8'd96: begin reg_addr = 8'h91; reg_data = 8'h69; end
            8'd97: begin reg_addr = 8'h91; reg_data = 8'h75; end
            8'd98: begin reg_addr = 8'h91; reg_data = 8'h7E; end
            8'd99: begin reg_addr = 8'h91; reg_data = 8'h88; end
            8'd100: begin reg_addr = 8'h91; reg_data = 8'h8F; end
            8'd101: begin reg_addr = 8'h91; reg_data = 8'h96; end
            8'd102: begin reg_addr = 8'h91; reg_data = 8'hA3; end
            8'd103: begin reg_addr = 8'h91; reg_data = 8'hAF; end
            8'd104: begin reg_addr = 8'h91; reg_data = 8'hC4; end
            8'd105: begin reg_addr = 8'h91; reg_data = 8'hD7; end
            8'd106: begin reg_addr = 8'h91; reg_data = 8'hE8; end
            8'd107: begin reg_addr = 8'h91; reg_data = 8'h20; end
            8'd108: begin reg_addr = 8'h92; reg_data = 8'h00; end
            8'd109: begin reg_addr = 8'h93; reg_data = 8'h06; end
            8'd110: begin reg_addr = 8'h93; reg_data = 8'hE3; end
            8'd111: begin reg_addr = 8'h93; reg_data = 8'h05; end
            8'd112: begin reg_addr = 8'h93; reg_data = 8'h05; end
            8'd113: begin reg_addr = 8'h93; reg_data = 8'h00; end
            8'd114: begin reg_addr = 8'h93; reg_data = 8'h04; end
            8'd115: begin reg_addr = 8'h93; reg_data = 8'h00; end
            8'd116: begin reg_addr = 8'h93; reg_data = 8'h00; end
            8'd117: begin reg_addr = 8'h93; reg_data = 8'h00; end
            8'd118: begin reg_addr = 8'h93; reg_data = 8'h00; end
            8'd119: begin reg_addr = 8'h93; reg_data = 8'h00; end
            8'd120: begin reg_addr = 8'h93; reg_data = 8'h00; end
            8'd121: begin reg_addr = 8'h93; reg_data = 8'h00; end
            8'd122: begin reg_addr = 8'h96; reg_data = 8'h00; end
            8'd123: begin reg_addr = 8'h97; reg_data = 8'h08; end
            8'd124: begin reg_addr = 8'h97; reg_data = 8'h19; end
            8'd125: begin reg_addr = 8'h97; reg_data = 8'h02; end
            8'd126: begin reg_addr = 8'h97; reg_data = 8'h0C; end
            8'd127: begin reg_addr = 8'h97; reg_data = 8'h24; end
            8'd128: begin reg_addr = 8'h97; reg_data = 8'h30; end
            8'd129: begin reg_addr = 8'h97; reg_data = 8'h28; end
            8'd130: begin reg_addr = 8'h97; reg_data = 8'h26; end
            8'd131: begin reg_addr = 8'h97; reg_data = 8'h02; end
            8'd132: begin reg_addr = 8'h97; reg_data = 8'h98; end
            8'd133: begin reg_addr = 8'h97; reg_data = 8'h80; end
            8'd134: begin reg_addr = 8'h97; reg_data = 8'h00; end
            8'd135: begin reg_addr = 8'h97; reg_data = 8'h00; end
            8'd136: begin reg_addr = 8'hA4; reg_data = 8'h00; end
            8'd137: begin reg_addr = 8'hA8; reg_data = 8'h00; end
            8'd138: begin reg_addr = 8'hC5; reg_data = 8'h11; end
            8'd139: begin reg_addr = 8'hC6; reg_data = 8'h51; end
            8'd140: begin reg_addr = 8'hBF; reg_data = 8'h80; end
            8'd141: begin reg_addr = 8'hC7; reg_data = 8'h10; end
            8'd142: begin reg_addr = 8'hB6; reg_data = 8'h66; end
            8'd143: begin reg_addr = 8'hB8; reg_data = 8'hA5; end
            8'd144: begin reg_addr = 8'hB7; reg_data = 8'h64; end
            8'd145: begin reg_addr = 8'hB9; reg_data = 8'h7C; end
            8'd146: begin reg_addr = 8'hB3; reg_data = 8'hAF; end
            8'd147: begin reg_addr = 8'hB4; reg_data = 8'h97; end
            8'd148: begin reg_addr = 8'hB5; reg_data = 8'hFF; end
            8'd149: begin reg_addr = 8'hB0; reg_data = 8'hC5; end
            8'd150: begin reg_addr = 8'hB1; reg_data = 8'h94; end
            8'd151: begin reg_addr = 8'hB2; reg_data = 8'h0F; end
            8'd152: begin reg_addr = 8'hC4; reg_data = 8'h5C; end
            8'd153: begin reg_addr = 8'hC3; reg_data = 8'hFD; end
            8'd154: begin reg_addr = 8'h7F; reg_data = 8'h00; end
            8'd155: begin reg_addr = 8'hE5; reg_data = 8'h1F; end
            8'd156: begin reg_addr = 8'hE1; reg_data = 8'h67; end
            8'd157: begin reg_addr = 8'hDD; reg_data = 8'h7F; end
            8'd158: begin reg_addr = 8'hDA; reg_data = 8'h00; end
            8'd159: begin reg_addr = 8'hE0; reg_data = 8'h00; end
            8'd160: begin reg_addr = 8'h05; reg_data = 8'h00; end

            8'd161: begin reg_addr = 8'hFF; reg_data = 8'h00; end
            8'd162: begin reg_addr = 8'h05; reg_data = 8'h01; end
            8'd163: begin reg_addr = 8'hFF; reg_data = 8'h01; end
            8'd164: begin reg_addr = 8'h12; reg_data = 8'h40; end
            8'd165: begin reg_addr = 8'h03; reg_data = 8'h0A; end
            8'd166: begin reg_addr = 8'h32; reg_data = 8'h09; end
            8'd167: begin reg_addr = 8'h17; reg_data = 8'h11; end
            8'd168: begin reg_addr = 8'h18; reg_data = 8'h43; end
            8'd169: begin reg_addr = 8'h19; reg_data = 8'h00; end
            8'd170: begin reg_addr = 8'h1A; reg_data = 8'h4B; end
            8'd171: begin reg_addr = 8'h37; reg_data = 8'hC0; end
            8'd172: begin reg_addr = 8'h4F; reg_data = 8'hCA; end
            8'd173: begin reg_addr = 8'h50; reg_data = 8'hA8; end
            8'd174: begin reg_addr = 8'h5A; reg_data = 8'h23; end
            8'd175: begin reg_addr = 8'h6D; reg_data = 8'h00; end
            8'd176: begin reg_addr = 8'h3D; reg_data = 8'h38; end
            8'd177: begin reg_addr = 8'h39; reg_data = 8'h92; end
            8'd178: begin reg_addr = 8'h35; reg_data = 8'hDA; end
            8'd179: begin reg_addr = 8'h22; reg_data = 8'h1A; end
            8'd180: begin reg_addr = 8'h37; reg_data = 8'hC3; end
            8'd181: begin reg_addr = 8'h23; reg_data = 8'h00; end
            8'd182: begin reg_addr = 8'h34; reg_data = 8'hC0; end
            8'd183: begin reg_addr = 8'h06; reg_data = 8'h88; end
            8'd184: begin reg_addr = 8'h07; reg_data = 8'hC0; end
            8'd185: begin reg_addr = 8'h0D; reg_data = 8'h87; end
            8'd186: begin reg_addr = 8'h0E; reg_data = 8'h41; end
            8'd187: begin reg_addr = 8'h42; reg_data = 8'h03; end
            8'd188: begin reg_addr = 8'h4C; reg_data = 8'h00; end
            8'd189: begin reg_addr = 8'hFF; reg_data = 8'h00; end
            8'd190: begin reg_addr = 8'hE0; reg_data = 8'h04; end
            8'd191: begin reg_addr = 8'hC0; reg_data = 8'h64; end
            8'd192: begin reg_addr = 8'hC1; reg_data = 8'h4B; end
            8'd193: begin reg_addr = 8'h8C; reg_data = 8'h00; end
            8'd194: begin reg_addr = 8'h51; reg_data = 8'hC8; end
            8'd195: begin reg_addr = 8'h52; reg_data = 8'h96; end
            8'd196: begin reg_addr = 8'h53; reg_data = 8'h00; end
            8'd197: begin reg_addr = 8'h54; reg_data = 8'h00; end
            8'd198: begin reg_addr = 8'h55; reg_data = 8'h00; end
            8'd199: begin reg_addr = 8'h57; reg_data = 8'h00; end
            8'd200: begin reg_addr = 8'h5A; reg_data = 8'hC8; end
            8'd201: begin reg_addr = 8'h5B; reg_data = 8'h96; end
            8'd202: begin reg_addr = 8'h5C; reg_data = 8'h00; end
            8'd203: begin reg_addr = 8'h86; reg_data = 8'h3D; end
            8'd204: begin reg_addr = 8'h50; reg_data = 8'h80; end
            8'd205: begin reg_addr = 8'hFF; reg_data = 8'h01; end
            8'd206: begin reg_addr = 8'h11; reg_data = 8'h87; end
            8'd207: begin reg_addr = 8'hFF; reg_data = 8'h00; end
            8'd208: begin reg_addr = 8'hD3; reg_data = 8'h88; end
            8'd209: begin reg_addr = 8'h05; reg_data = 8'h00; end

            8'd210: begin reg_addr = 8'hFF; reg_data = 8'h00; end
            8'd211: begin reg_addr = 8'hE0; reg_data = 8'h04; end
            8'd212: begin reg_addr = 8'hDA; reg_data = 8'h08; end
            8'd213: begin reg_addr = 8'hC2; reg_data = 8'h0E; end
            8'd214: begin reg_addr = 8'hD7; reg_data = 8'h03; end
            8'd215: begin reg_addr = 8'hE1; reg_data = 8'h77; end
            8'd216: begin reg_addr = 8'hE0; reg_data = 8'h00; end
            8'd217: begin reg_addr = 8'hFF; reg_data = 8'h01; end
            8'd218: begin reg_addr = 8'h15; reg_data = 8'h00; end
            8'd219: begin reg_addr = 8'hFF; reg_data = 8'h00; end
            8'd220: begin is_delay = 1'b1; delay_ms = 24'd5; end

            default: begin
                table_end = 1'b1;
            end

            // 状态机分支结束，未命中的情况由默认分支回到安全状态。
        endcase
    end

endmodule
