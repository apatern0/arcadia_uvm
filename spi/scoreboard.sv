`include "uvm/if.sv"

import uvm_pkg::*;
`include "uvm_macros.svh"

class spi_scoreboard extends uvm_scoreboard;
	`uvm_component_utils (spi_scoreboard)
	
	`uvm_analysis_imp_decl ( _sent_cmd )
	`uvm_analysis_imp_decl ( _recv_cmd )

	uvm_analysis_imp_sent_cmd #( spi_command , spi_scoreboard ) m_sent_imp ;
	uvm_analysis_imp_recv_cmd #( spi_command , spi_scoreboard ) m_recv_imp ;

	spi_command cmd_sent_queue[$];
	spi_command cmd_recv_queue[$];

	function new (string name = "spi_scoreboard", uvm_component parent);
		super.new (name, parent);
	endfunction

	function void build_phase (uvm_phase phase);
		m_sent_imp = new ("m_sent_imp", this);
		m_recv_imp = new ("m_recv_imp", this);
	endfunction

	virtual function void write_sent_cmd (spi_command data);
		`uvm_info ("SB", $sformatf("%m - Command sent: %s", data.convert2str()), UVM_DEBUG)

		cmd_sent_queue.push_front(data);
	endfunction

	virtual function void write_recv_cmd (spi_command just_recv);
		spi_command last_sent;

		`uvm_info ("SB", $sformatf("%m - Command received: %s", just_recv.convert2str()), UVM_DEBUG)

		if(cmd_sent_queue.size() == 0)
			`uvm_warning("SB", $sformatf("Received an SPI Command, but none was sent! %s", just_recv.convert2str()))
		else begin
			last_sent = cmd_sent_queue.pop_back();
			if(last_sent.cmd != just_recv.cmd)
				`uvm_warning ("SB", $sformatf("%m - SPI Commands do not match! Last Sent: %s - Just received: %s", last_sent.convert2str(), just_recv.convert2str()))
			else
				`uvm_info ("SB", $sformatf("%m - SPI Command ECHO is ok! %s", just_recv.convert2str()), UVM_HIGH)


			cmd_recv_queue.push_front(just_recv);
		end
	endfunction

endclass
