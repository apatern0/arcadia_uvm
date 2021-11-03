`timescale 1ns/100fs

`include "tb_defines.sv"
`include "arcadia_ver.sv"
`include "uvm/env.sv"
`include "uvm/tests.sv"

`include "CG.sv"
`include "Deserializer.sv"
`include "decoder.sv"

import uvm_pkg::*;
`include "uvm_macros.svh"

module tb ();

// Clock
logic clock;
always #(`ARCADIA_CHIP_CLK_PERIOD_NS/2) clock = ~clock;

// Chip and wires
`include "bottom_padframe_tb_wires.v"
`include "top_padframe_tb_wires.v"

wire Serializers [0:15];
assign Serializers[ 0 ] = Serializer0;
assign Serializers[ 1 ] = Serializer1;
assign Serializers[ 2 ] = Serializer2;
assign Serializers[ 3 ] = Serializer3;
assign Serializers[ 4 ] = Serializer4;
assign Serializers[ 5 ] = Serializer5;
assign Serializers[ 6 ] = Serializer6;
assign Serializers[ 7 ] = Serializer7;
assign Serializers[ 8 ] = Serializer8;
assign Serializers[ 9 ] = Serializer9;
assign Serializers[ 10 ] = Serializer10;
assign Serializers[ 11 ] = Serializer11;
assign Serializers[ 12 ] = Serializer12;
assign Serializers[ 13 ] = Serializer13;
assign Serializers[ 14 ] = Serializer14;
assign Serializers[ 15 ] = Serializer15;

// Instantiating the interface
chip_if _if (clock);

Chip chip (.*);

// Diodes
logic [`ARCADIA_MATRIX_HEIGHT-1:0][`ARCADIA_MATRIX_WIDTH-1:0] i_diodes;
assign i_diodes = _if.diodes;
`include "diode_assignments.sv"

CG clock_gen (.CK(clock), .E(_if.clock_enable), .GCK(Clock));
assign Reset     = _if.chip_reset;
assign TestPulse = _if.test_pulse;

//assign _if.timestamp = chip.per.event_id;

// Spi
spi_master #(.slaves(1), .d_width(24)) spi_master (
	.cpol      ( 1'b0 ),
	.cpha      ( 1'b1 ),
	.clk_div   ( 10 ),

	.cont      ( 1'b0 ),
	.addr      ( 1'b0 ),

	.clock     ( Clock ),
	.nres      ( ~_if.spi_reset ),
	.enable    ( _if.spi_enable ),
    .tx_data   ( _if.spi_tx ),
    .rx_data   ( _if.spi_rx ),
    .busy      ( _if.spi_busy ),

    .sclk      ( SpiClock ),
    .miso      ( SpiSdo ),
    .mosi      ( SpiSdi ), 
    .ss_n      ( SpiSl )
);

/*
* Monitors and Probes
*/
int packet_counter [`ARCADIA_PERIPHERY_SECTIONS-1:0];
int idle_counter [`ARCADIA_PERIPHERY_SECTIONS-1:0];
wire [`ARCADIA_PERIPHERY_SECTIONS-1:0] ser_sample;
wire [`ARCADIA_PERIPHERY_SECTIONS-1:0] ser_synchronized;
wire [`ARCADIA_PERIPHERY_SECTIONS-1:0] [39:0] ser_word;
wire [`ARCADIA_PERIPHERY_SECTIONS-1:0] [3:0] des_delay;

genvar sec, col, core, pr;

generate
if(arcadia_ver::stages[0] == 1) begin
	serializer_probe_if_array      serializer_probes;

	for(sec=0; sec<`ARCADIA_SECTIONS; sec++) begin: deserializers_gen
		wire [31:0] decoded;
		wire decoded_ready;

		Deserializer #(.WORDS(4)) des40 (
			.Delay        ( des_delay[sec] ),
			.Clock        ( Clock ),
			.Reset        ( Reset ),
			.StreamInput  ( Serializers[sec] ),
			.SyncWord     ( 40'h9f1835f283 ),
			.Sample       ( ser_sample[sec] ),
			.Synchronized ( ser_synchronized[sec] ),
			.WordOutput   ( ser_word[sec] )
		);
		Decoder dec (.Clock(ser_sample[sec]), .R(Reset), .I(ser_word[sec]), .O(decoded), .Ready(decoded_ready));

		initial packet_counter[sec] = 0;
		always @(posedge Clock) if(ser_sample[sec]) begin
			if(decoded_ready)
				packet_counter[sec]++;

			if(ser_synchronized[sec])
				idle_counter[sec]++;
			else
				idle_counter[sec] = 0;
		end

		serializer_probe_if serializer_probe (.Clock(ser_sample[sec]), .Ready(decoded_ready), .Data(decoded));

		assign serializer_probes[sec] = serializer_probe;
	end

	assign _if.serializer_idle = idle_counter;
	
	initial uvm_config_db#(serializer_probe_if_array)::set(null, "*.hit_ag.m*", "serializer_probes", serializer_probes);
end

if(arcadia_ver::stages[1] == 1) begin
	pre_serializer_probe_if_array pre_serializer_probes;

	for(sec=0; sec<`ARCADIA_SECTIONS; sec++) begin
		// Pre-serializer probes
		bind Serializer : chip.ser_gen[sec].ser pre_serializer_probe_if pre_serializer_probe (
			.Clock    ( sample_word_clock ),
			.Data     ( WordInput )
		);
		assign pre_serializer_probes[sec] = chip.ser_gen[sec].ser.pre_serializer_probe;
	end

	initial uvm_config_db#(pre_serializer_probe_if_array)::set(null, "*.hit_ag.m*", "pre_serializer_probes", pre_serializer_probes);
end

`ifndef MATRIX_SDF
`ifndef SECTION_SDF
if(arcadia_ver::stages[2] == 1 || arcadia_ver::stages[3] == 1) begin
	for(sec=0; sec<`ARCADIA_SECTIONS; sec++) begin
		// Instantiate cru_probe_mods
		bind SectionReadoutUnit : chip.mat.section_gen[sec].sec.eos.cru cru_probe_if_mod cru_probe_mod (
			.clock (gated_clock),
			.*
		);
	end
end
`endif
`endif

if(arcadia_ver::stages[2] == 1) begin
	colmem_out_probe_if_array colmem_out_probes;

	for(sec=0; sec<`ARCADIA_SECTIONS; sec++) begin
		for(col=0; col<`ARCADIA_SECTION_COLUMNS; col++) begin
			assign colmem_out_probes[sec][col] = chip.mat.section_gen[sec].sec.eos.cru.cru_probe_mod.probe_gen[col].colmem_out_probe;
		end
	end

	initial uvm_config_db#(colmem_out_probe_if_array)::set(null, "*.hit_ag.m*", "colmem_out_probes", colmem_out_probes);
end

if(arcadia_ver::stages[3] == 1) begin
	col_probe_if_array col_probes;

`ifndef MATRIX_SYN
`ifndef SECTION_SDF
	for(sec=0; sec<`ARCADIA_SECTIONS; sec++) begin
		for(col=0; col<`ARCADIA_SECTION_COLUMNS; col++) begin
			assign col_probes[sec][col]        = chip.mat.section_gen[sec].sec.eos.cru.cru_probe_mod.probe_gen[col].col_probe;
		end
	end
`else
	for(sec=0; sec<`ARCADIA_SECTIONS; sec++) begin
		// Instantiate cru_probe_mods
		bind Eos : chip.mat.section_gen[sec].sec_wrapper.Section.eos col_probe_if_mod col_probe_mod (
			.clock (gated_clock),
			.*
		);
		for(col=0; col<`ARCADIA_SECTION_COLUMNS; col++) begin
			assign col_probes[sec][col]        = chip.mat.section_gen[sec].sec_wrapper.Section.eos.col_probe_mod.probe_gen[col].col_probe;
		end
	end
`endif
`else
	`include "col_probes.sv"
`endif

	initial uvm_config_db#(col_probe_if_array)::set(null, "*.hit_ag.m*", "col_probes", col_probes);
end

if(arcadia_ver::stages[4] == 1) begin
	region_probe_if_array region_probes;

	for(sec=0; sec<`ARCADIA_SECTIONS; sec++) begin
		for(col=0; col<`ARCADIA_SECTION_COLUMNS; col++) begin
			for(core=0; core<`ARCADIA_COLUMN_CORES; core++) begin
				bind Core : chip.mat.section_gen[sec].sec.col_gen[col].core_gen[core].core core_probe_if_mod core_probe (.*);
				assign chip.mat.section_gen[sec].sec.col_gen[col].core_gen[core].core.core_probe.core_address = core;
		
				for(pr=0; pr<`ARCADIA_CORE_PRS; pr++) begin
					assign region_probes[sec][col][core][pr] = chip.mat.section_gen[sec].sec.col_gen[col].core_gen[core].core.core_probe.probe_gen[pr].region_probe;
				end
			end
		end
	end

	initial uvm_config_db#(region_probe_if_array)::set(null, "*.hit_ag.m*", "region_probes", region_probes);
end
endgenerate

initial begin
	clock = 0;

	uvm_config_db#(virtual chip_if)::set(null, "*", "chip_vif", _if);

	run_test("base_test");
end

endmodule
