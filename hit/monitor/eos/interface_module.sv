module cru_probe_if_mod (
	input wire clock,
	input wire [`ARCADIA_SECTION_COLUMNS-1:0] [`ARCADIA_CORE_DATA_BITS-1:0] colmem_out,
	input wire [`ARCADIA_SECTION_COLUMNS-1:0] colmem_read,

	input CoreIfDesc [`ARCADIA_SECTION_COLUMNS-1:0] fromColumns,
	input CoreIfAsc [`ARCADIA_SECTION_COLUMNS-1:0] toColumns
);

genvar col;
generate
for(col=0; col<`ARCADIA_SECTION_COLUMNS; col++) begin: probe_gen
	colmem_out_probe_if colmem_out_probe (.Clock (clock), .Read (colmem_read[col]), .Data (colmem_out[col]));

	col_probe_if col_probe (.Clock (toColumns[col].Read), .fromColumn (fromColumns[col]), .toColumn (toColumns[col]));
end
endgenerate
endmodule


module col_probe_if_mod (
	input wire clock,
	input CoreIfDesc [`ARCADIA_SECTION_COLUMNS-1:0] fromColumns,
	input CoreIfAsc [`ARCADIA_SECTION_COLUMNS-1:0] toColumns
);

genvar col;
generate
for(col=0; col<`ARCADIA_SECTION_COLUMNS; col++) begin: probe_gen
	col_probe_if col_probe (.Clock (toColumns[col].Read), .fromColumn (fromColumns[col]), .toColumn (toColumns[col]));
end
endgenerate
endmodule
