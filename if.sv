`ifndef ARCADIA_UVM_IF
`define ARCADIA_UVM_IF

`include "defines.sv"
`include "interfaces.sv"

import uvm_pkg::*;
`include "uvm_macros.svh"

interface chip_if (input bit clock);
	logic [`ARCADIA_MATRIX_HEIGHT-1:0][`ARCADIA_MATRIX_WIDTH-1:0] diodes;

	logic test_pulse;

  	logic clock_enable;
  	logic chip_reset;

  	logic spi_reset;
	logic spi_enable;
	logic [23:0] spi_tx;
	logic [23:0] spi_rx;
	logic spi_busy;

	logic [`ARCADIA_EVENT_ID_BITS-1:0] timestamp;
	logic [`ARCADIA_EVENT_ID_BITS-1:0] timestamp_tb;

	logic [`ARCADIA_SECTIONS-1:0] [31:0] packet;
	logic [`ARCADIA_SECTIONS-1:0] packet_ready;

	int serializer_idle [`ARCADIA_PERIPHERY_SECTIONS-1:0];

	clocking cb @(posedge clock);
		default input #1step output #3ns;
		output clock_enable;

		output chip_reset;
		output spi_reset;
		output spi_enable;
		output spi_tx;
		output timestamp_tb;

		input timestamp;
		input spi_rx;
		input spi_busy;
		input packet;
		input packet_ready;
		input serializer_idle;
	endclocking
endinterface

`endif
