interface serializer_probe_if (
	input wire Clock,
	input wire Ready,
	input wire [31:0] Data
);
	task edge_ready();
		@(posedge Clock iff Ready);
		#1ns;
	endtask

	task wait_and_get(output [31:0] res);
		edge_ready();
		assign res = Data;
	endtask
endinterface
typedef virtual serializer_probe_if serializer_probe_if_array [`ARCADIA_SECTIONS-1:0];

class serializers_monitor extends hit_monitor;
	`uvm_component_utils(serializers_monitor)
	function new(string name="serializers_monitor", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	serializer_probe_if_array serializer_probes;
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		if (!uvm_config_db#(serializer_probe_if_array)::get(this, "", "serializer_probes", serializer_probes))
			`uvm_fatal("MON", "Could not get serializer_probes")
	endfunction

	virtual task active_phase;
		for(int i=0; i<`ARCADIA_SECTIONS; i++) fork
			automatic int sec = i;
			forever begin
				logic [31:0] packet;
		
				`uvm_info(mon_name, $sformatf("Listening on data from serializer %2d...", sec), UVM_DEBUG);
				serializer_probes[sec].wait_and_get(packet);
				cfg.recv_pkt[stage]++;

				if(packet[7:0] == 0) begin
					cfg.recv_pkt_null[stage]++;
					`uvm_warning(mon_name, $sformatf("Time %7d. Receiving null packet from serializer %2d...", $time, sec));

					if (stop_on_null) $stop;
				end else begin
					`uvm_info(mon_name, $sformatf("Received packet 0b%b w/ts %4d.", packet, packet[28:25]), UVM_HIGH);
					analyze_packet (
						packet[7:0],
						packet[16:8],
						packet[20:17],
						packet[24:21],
						packet[28:25],
						packet[31:29]
					);
				end
			end
		join_none
	endtask
endclass
