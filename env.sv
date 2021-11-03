`include "uvm/if.sv"
`include "uvm/base/driver.sv"
`include "uvm/spi/agent.sv"
`include "uvm/spi/scoreboard.sv"
`include "uvm/hit/agent.sv"
`include "uvm/hit/scoreboard.sv"
`include "cfg_defines.v"

import uvm_pkg::*;
`include "uvm_macros.svh"

class env extends uvm_env;
	`uvm_component_utils(env)

	function new(string name="env", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	virtual chip_if   vif;
	cfg_t  cfg;

	base_driver      base_drv;
	hit_agent        hit_ag;
	hit_scoreboard   hit_sb;
	spi_agent        spi_ag;
	spi_scoreboard   spi_sb;

	bit stop_on_null;

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		if (!uvm_config_db#(virtual chip_if)::get(this, "", "chip_vif", vif))
			`uvm_fatal("MON", "Could not get vif")

		if (!uvm_config_db#(cfg_t)::get(this, "", "cfg", cfg))
			`uvm_fatal("TEST", "Did not get cfg")

		base_drv  = base_driver::type_id::create("base_drv", this);

		hit_ag  = hit_agent::type_id::create("hit_ag", this);
		hit_sb  = hit_scoreboard::type_id::create("hit_sb", this);

		spi_ag  = spi_agent::type_id::create("spi_ag", this);
		spi_sb  = spi_scoreboard::type_id::create("spi_sb", this);
	endfunction

	virtual task run_phase(uvm_phase phase);
		forever begin
			repeat((2**7)*10) @(posedge vif.clock);
			cfg.timestamp++;

			vif.timestamp_tb = cfg.timestamp;
		end
	endtask

	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);

		hit_ag.d0.m_sent_imp.connect(hit_sb.m_sent_imp);
		hit_ag.d0.m_dead_imp.connect(hit_sb.m_dead_imp);

		if(arcadia_ver::stages[4] == 1) hit_ag.m4.m_recv_imp.connect(hit_sb.m_recv_imp);
		if(arcadia_ver::stages[3] == 1) hit_ag.m3.m_recv_imp.connect(hit_sb.m_recv_imp);
		if(arcadia_ver::stages[2] == 1) hit_ag.m2.m_recv_imp.connect(hit_sb.m_recv_imp);
		if(arcadia_ver::stages[1] == 1) hit_ag.m1.m_recv_imp.connect(hit_sb.m_recv_imp);
		if(arcadia_ver::stages[0] == 1) hit_ag.m0.m_recv_imp.connect(hit_sb.m_recv_imp);

		spi_ag.d0.m_sent_imp.connect(spi_sb.m_sent_imp);
		spi_ag.m0.m_recv_imp.connect(spi_sb.m_recv_imp);
	endfunction

	virtual task reset_phase(uvm_phase phase);
		cfg.sent_pix = 0;

		for(int i=0; i<=arcadia_ver::num_stages; i++) begin
			cfg.recv_pkt[i] = 0;
			cfg.recv_pkt_null[i] = 0;
			cfg.recv_pix[i] = 0;
		end
	endtask

	virtual task configure_phase(uvm_phase phase);
		phase.raise_objection(this);

		`uvm_info("CFG", $sformatf("%m - Configuring chip!"), UVM_LOW)

		// Disable Section readout
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_POINTER, {1'b0, 3'b010, 6'd0, 6'd`ARCADIA_GCR_SECTION_READ_MASK_WORD});
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_DATA, 16'hFFFF);

		// Send a reset chip pulse
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_ICR0, {12'd0, 1'b1, 3'b001});

		// Change Token Counter/Max Reads/Timing Clock/Readout Clock
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_POINTER, {1'b0, 3'b010, 6'd0, 6'd`ARCADIA_GCR_READOUT_CLK_DIVIDER_WORD});
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_DATA, {4'h8, 4'h0, 4'h5, 4'h0});

		// Send a reset chip pulse
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_ICR0, {12'd0, 1'b1, 3'b001});

		// Initialization. Needed for resetting cores
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_POINTER, {1'b0, 3'b010, 6'd0, 6'd`ARCADIA_GCR_HELPER_SECCFG_SECTIONS_WORD});
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_DATA, 16'hFFFF);

		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_POINTER, {1'b0, 3'b010, 6'd0, 6'd`ARCADIA_GCR_HELPER_SECCFG_COLUMNS_WORD});
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_DATA, 16'hFFFF);

		// Broadcast the default configuration
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_POINTER, {1'b0, 3'b010, 6'd0, 6'd`ARCADIA_GCR_HELPER_SECCFG_PRSTART_WORD});
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_DATA, {2'b10, 5'h1F, 9'h000});

		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_POINTER, {1'b0, 3'b010, 6'd0, 6'd`ARCADIA_GCR_HELPER_SECCFG_PRSTOP_WORD});
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_DATA, {7'h00, 9'h1FF});

		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_ICR0, 16'h0100);

		// Reset the pixels
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_POINTER, {1'b0, 3'b010, 6'd0, 6'd`ARCADIA_GCR_HELPER_SECCFG_PRSTART_WORD});
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_DATA, {2'b10, 5'h1F, 9'h000});

		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_POINTER, {1'b0, 3'b010, 6'd0, 6'd`ARCADIA_GCR_HELPER_SECCFG_PRSTOP_WORD});
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_DATA, {7'h7F, 9'h000});

		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_ICR0, 16'h0100);

		// Test CFG Write
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_POINTER, {1'b0, 3'b010, 6'd0, 6'd`ARCADIA_GCR_HELPER_SECCFG_PRSTART_WORD});
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_DATA, {2'b01, 5'h1E, 9'h00E});

		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_POINTER, {1'b0, 3'b010, 6'd0, 6'd`ARCADIA_GCR_HELPER_SECCFG_PRSTOP_WORD});
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_DATA, {7'h00, 9'h001});

		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_ICR0, 16'h0100);

		// Test CFG Write
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_POINTER, {1'b0, 3'b010, 6'd0, 6'd`ARCADIA_GCR_HELPER_SECCFG_PRSTART_WORD});
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_DATA, {2'b10, 5'h1E, 9'h00E});

		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_POINTER, {1'b0, 3'b010, 6'd0, 6'd`ARCADIA_GCR_HELPER_SECCFG_PRSTOP_WORD});
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_DATA, {7'h00, 9'h001});

		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_ICR0, 16'h0100);

		// Broadcast the default configuration
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_POINTER, {1'b0, 3'b010, 6'd0, 6'd`ARCADIA_GCR_HELPER_SECCFG_PRSTART_WORD});
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_DATA, {2'b10, 5'h1F, 9'h000});

		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_POINTER, {1'b0, 3'b010, 6'd0, 6'd`ARCADIA_GCR_HELPER_SECCFG_PRSTOP_WORD});
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_DATA, {7'h00, 9'h1FF});

		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_ICR0, 16'h0100);

		// Send a pulse resets for the CRUs
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_ICR0, {12'd0, 1'b1, 3'b001});

		// Send a reset chip pulse, clears async reset flops
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_ICR0, {12'd0, 1'b1, 3'b001});

		// Disable default configuration
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_POINTER, {1'b0, 3'b010, 6'd0, 6'd`ARCADIA_GCR_FORCE_ENABLE_INJECTION_WORD});
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_DATA, {16'h0000});

		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_POINTER, {1'b0, 3'b010, 6'd0, 6'd`ARCADIA_GCR_FORCE_DISABLE_MASK_WORD});
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_DATA, {16'h0000});

		// Change Token Counter/Max Reads/Timing Clock/Readout Clock
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_POINTER, {1'b0, 3'b010, 6'd0, 6'd`ARCADIA_GCR_READOUT_CLK_DIVIDER_WORD});
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_DATA, {4'h8, 4'hF, 4'h6, 4'h0});

		// Enable Section Readout
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_POINTER, {1'b0, 3'b010, 6'd0, 6'd`ARCADIA_GCR_SECTION_READ_MASK_WORD});
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_DATA, 16'h0000);

		// Send a reset chip pulse, clears sync reset flops
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_ICR0, {12'd0, 1'b1, 3'b001});

		// Test vector
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_POINTER, {1'b0, 3'b010, 6'd0, 6'd`ARCADIA_GCR_BIAS0_VCAL_LO_WORD});
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_DATA, 16'hFFFF);

		// Enable Clock Gating to EOSs, Sections, and if needed, Space Mode
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_POINTER, {1'b0, 3'b010, 6'd0, 6'd`ARCADIA_GCR_OPERATION_WORD});
`ifdef ARCADIA_SPACE_MODE
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_DATA, {1'b1, 3'd1, 3'd1, 1'b1, 1'b0, 1'b1, 1'b1, 3'd4, 1'b0, 1'b1});
`else
		spi_ag.d0.send_command(phase, `ARCADIA_SPI_WRITE_DATA, {1'b1, 3'd3, 3'd3, 1'b1, 1'b0, 1'b1, 1'b1, 3'd4, 1'b0, 1'b0});
`endif

		phase.drop_objection(this);
	endtask

	virtual task post_configure_phase(uvm_phase phase);
		cluster_hit c;
		string rpt;
		super.post_configure_phase(phase);

		phase.raise_objection(this);

		hit_sb.report_level = UVM_NONE;
		hit_sb.clear();

		`uvm_info("ENV", "Sending kick-off injections", UVM_LOW);

		c = cluster_hit::type_id::create("c", this);
		c.inject_pix(`ARCADIA_MATRIX_HEIGHT-1,0,400,400); c.start(hit_ag.s0);
	
		@(cfg.recv_pkt[0]);
		c = cluster_hit::type_id::create("c", this);
		c.inject_pix(2,0,400,400); c.inject_pix(3,0,400,400); c.inject_pix(4,0,400,400); c.start(hit_ag.s0);
	
		@(cfg.recv_pkt[0]);
		c = cluster_hit::type_id::create("c", this);
		c.inject_pix(`ARCADIA_MATRIX_HEIGHT/2-1,0,400,400); c.start(hit_ag.s0);

		@(cfg.recv_pkt[0]);
		c = cluster_hit::type_id::create("c", this);
		c.inject_pix(`ARCADIA_MATRIX_HEIGHT/2-1,2,400,400); c.start(hit_ag.s0);

		@(cfg.recv_pkt[0]);
		c = cluster_hit::type_id::create("c", this);
		c.inject_pix(`ARCADIA_MATRIX_HEIGHT/2-1,16,400,400); c.start(hit_ag.s0);
	
		@(cfg.recv_pkt[0]);
		c = cluster_hit::type_id::create("c", this);
		c.inject_pix(2,0,400,400); c.inject_pix(3,0,400,400); c.inject_pix(4,0,400,400); c.start(hit_ag.s0);
	
		@(cfg.recv_pkt[0]);
		hit_sb.report();
		hit_sb.adjust_timestamp();

		c = cluster_hit::type_id::create("c", this);
		c.inject_pix(`ARCADIA_MATRIX_HEIGHT/2-1,16,400,400); c.start(hit_ag.s0);
	
		@(cfg.recv_pkt[0]);
		c = cluster_hit::type_id::create("c", this);
		c.inject_pix(2,0,400,400); c.inject_pix(3,0,400,400); c.inject_pix(4,0,400,400); c.start(hit_ag.s0);
	
		@(cfg.recv_pkt[0]);
		hit_sb.report();
		
		rpt = "These hits have been tracked so far:\n";
		foreach (hit_sb.stage_queue[0][i])
			rpt = {rpt, hit_sb.stage_queue[0][i].convert2str(), "\n"};

		`uvm_info("ENV", rpt, UVM_NONE);

		phase.drop_objection(this);
	endtask

	virtual task post_main_phase(uvm_phase phase);
		int idle;

		super.post_main_phase(phase);
		phase.raise_objection(this);

		do begin
			idle = 0;

			#1us;

			for(int ser=0; ser<`ARCADIA_SECTIONS; ser++)
				if(vif.serializer_idle[ser] > 1000) begin
					`uvm_info("ENV", $sformatf("Serializer %2d is idle.", ser), UVM_NONE);
					idle++;
				end
		end while (idle < `ARCADIA_SECTIONS-1);

		`uvm_info("ENV", "All serializers are idle! Finishing simulation...", UVM_NONE);
		phase.drop_objection(this);
	endtask

	virtual task shutdown_phase(uvm_phase phase);
		super.shutdown_phase(phase);

		phase.raise_objection(this);
		`uvm_info("ENV", "Now in post-main!", UVM_LOW);
		#10us;
		cfg.expiration_time = 1;
		hit_sb.check_expired();
		hit_sb.report(0);
		phase.drop_objection(this);
	endtask
endclass

