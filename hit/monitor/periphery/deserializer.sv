module Decoder (
	input  Clock,
	input  [19:0] I,
	output [31:0] O,
	output Ready
);

// 8b10b Decoding
wire [1:0] is_kcode;
wire [1:0] disp_out;
wire [1:0] code_err;
wire [1:0] disp_err;
logic disp_in_0;

decode8b10b dec8b10b_msb (
	.datain   ( I[19 -: 10] ),
	.dispin   ( disp_out[0] ),
	.dataout  ( {is_kcode[1], decoded[15 -: 8]} ),
	.dispout  ( disp_out[1] ),
	.code_err ( code_err[1] ),
	.disp_err ( disp_err[1] )
);

decode8b10b dec8b10b_lsb (
	.datain   ( I[9 -: 10] ),
	.dispin   ( disp_in_0 ),
	.dataout  ( {is_kcode[0], decoded[7 -: 8]} ),
	.dispout  ( disp_out[0] ),
	.code_err ( code_err[0] ),
	.disp_err ( disp_err[0] )
);

always @(posedge Clock or posedge Reset)
	if( Reset )
		disp_in_0 <= 1'b0;
	else
		disp_in_0 <= disp_out[1];

/*
* Packet reconstruction
*/
logic [31:0] decoded_packet;
logic [15:0] decoded_packet_lsb;
logic [15:0] decoded_packet_msb;
logic decoded_packet_ready;
logic decoded_packet_is_lsb;

always @(posedge Clock or posedge Reset) begin
   if(Reset) begin
	   decoded_packet_lsb <= 16'd0;
	   decoded_packet_msb <= 16'd0;
	   decoded_packet_ready <= 1'b0;
	   decoded_packet_is_lsb <= 1'b1;
   end else if (is_kcode[0] == 1'b1 && decoded[7 -: 8] == 8'hBC) begin
	   decoded_packet_lsb <= 16'd0;
	   decoded_packet_msb <= 16'd0;
	   decoded_packet_ready <= 1'b0;
	   decoded_packet_is_lsb <= 1'b1;
   end else if(~decoded_packet_is_lsb) begin	
	   decoded_packet_msb <= decoded;
	   decoded_packet_ready <= 1'b1;
	   decoded_packet_is_lsb <= 1'b1;
   end else begin //if(decoded_packet_is_lsb) begin	
	   decoded_packet_lsb <= decoded;
	   decoded_packet_ready <= 1'b0;
	   decoded_packet_is_lsb <= 1'b0;
   end
end

assign O = {decoded_packet_msb, decoded_packet_lsb};
endmodule
