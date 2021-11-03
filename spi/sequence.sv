`include "uvm/if.sv"

import uvm_pkg::*;
`include "uvm_macros.svh"

class spi_command extends uvm_sequence_item;
	`uvm_object_utils(spi_command)

	logic [3:0] cmd;
	logic [15:0] data;
	uvm_phase phase;

	virtual function string convert2str();
		string cmd_name;

		case (cmd)
		4'b0000:
			cmd_name = "WR_PNTR";
		4'b0001:
			cmd_name = "WR_DATA";
		4'b0010:
			cmd_name = "WR_STAT";
		4'b0011:
			cmd_name = "WR_ICR0";
		4'b0100:
			cmd_name = "WR_ICR1";
		4'b1000:
			cmd_name = "RD_PNTR";
		4'b1001:
			cmd_name = "RD_DATA";
		4'b1010:
			cmd_name = "RD_STAT";
		4'b1011:
			cmd_name = "RD_ICR0";
		4'b1100:
			cmd_name = "RD_ICR1";
		endcase

		return $sformatf("Command: %s - Payload: 0b%b (0h%x)", cmd_name, data, data);
	endfunction

	function new(string name = "spi_command");
		super.new(name);
	endfunction
endclass
