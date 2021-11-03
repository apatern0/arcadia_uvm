module core_probe_if_mod (
	input [`ARCADIA_CORE_PRS-1:0] [`ARCADIA_PR_DATA_BITS-1:0] region_hitmap
);

logic [`ARCADIA_CORE_ADDRESS_BITS-1:0] core_address;

genvar pr;
generate
for(pr=0; pr<`ARCADIA_CORE_PRS; pr++) begin: probe_gen
	region_probe_if region_probe (.region_hitmap(region_hitmap[pr]));
	assign region_probe.core_address = core_address;
	assign region_probe.pr_address = pr;
end
endgenerate
endmodule

