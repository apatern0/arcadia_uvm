interface colmem_out_probe_if (
	input wire Clock,
	input wire Read,
	input CoreDataIf Data
);

	clocking cb @ (posedge Clock);
		input Read, Data;
	endclocking

	task wait_and_get(output CoreDataIf res);
		@(cb iff cb.Read) 
			res = cb.Data;
	endtask
endinterface
typedef virtual colmem_out_probe_if colmem_out_probe_if_array [`ARCADIA_SECTIONS-1:0] [`ARCADIA_SECTION_COLUMNS-1:0];

class colmem_out_monitor extends hit_monitor;
	`uvm_component_utils(colmem_out_monitor)
	function new(string name="colmem_out_monitor", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	colmem_out_probe_if_array colmem_out_probes;
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		if (!uvm_config_db#(colmem_out_probe_if_array)::get(this, "", "colmem_out_probes", colmem_out_probes))
			`uvm_fatal("MON", "Could not get colmem_out_probes")
	endfunction

	virtual task active_phase;
		for(int i=0; i<`ARCADIA_SECTIONS; i++) for(int c=0; c<`ARCADIA_SECTION_COLUMNS; c++) fork
			automatic int sec = i;
			automatic int col = c;
			forever begin
				logic [31:0] packet;
				logic [`ARCADIA_CORE_PR_ADDRESS_BITS-1:0] hit_core_pr;
				logic [`ARCADIA_PR_DATA_BITS-1:0]         hit_data;
				logic [`ARCADIA_EVENT_ID_BITS-1:0]        hit_timestamp;

				`uvm_info(mon_name, $sformatf("Listening on data from sec %2d col %2d...", sec, col), UVM_DEBUG);
				colmem_out_probes[sec][col].wait_and_get(packet);
				cfg.recv_pkt[stage]++;

				{hit_timestamp, hit_core_pr, hit_data} = packet;

				if(packet[7:0] == 0) begin
					cfg.recv_pkt_null[stage]++;
					`uvm_warning(mon_name, $sformatf("Time %7d. Receiving null packet from colmem_out %2d...", $time, col));

					if (stop_on_null) $stop;
				end else begin
					`uvm_info(mon_name, $sformatf("Received packet 0b%b (sec %2d col %2d corepr %4d data 0b%8b) w/ts %4d.", packet, sec, col, hit_core_pr, hit_data, hit_timestamp), UVM_HIGH);
					analyze_packet(hit_data, hit_core_pr, col, sec, hit_timestamp, 4'd0);
				end // end else begin
			end // forever begin
		join_none
	endtask
endclass
