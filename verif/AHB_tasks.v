// =========== AHB bus tasks - crude models of bus activity =========================
// To use these tasks, include everything below this line, until the next ===== line
// Read and Write tasks do not restore the bus to idle, as another transaction might follow.
// Use AHBidle task immediately after read or write if no transaction follows immediately.

	reg [31:0] nextWdata = 32'h0;		// delayed data for write transactions
	reg [31:0] expectRdata = 32'h0;		// expected read data for read transactions
	reg [31:0] rExpectRead;				// store expected read data
	reg [4:0]  rReadType;               // store size and position of read data 
	reg checkRead;						// remember that read is in progress
	reg [31:0] readCapture = 32'h0;     // to capture read data on clock edge
	reg transState;						// state of our transaction - 1 if in data phase
	reg error = 1'b0;  // read error signal - asserted for one cycle AFTER read completes
	integer errCount = 0;				// error counter
    
// Task to simulate a write transaction on AHB Lite
	task AHBwrite ( 
			input [2:0] size,	// transaction width - BYTE, HALF or WORD
			input [31:0] addr,	// address
			input [31:0] data );	// data to be written, right-justified
		begin
			wait (HREADY == 1'b1);	// wait for ready signal - previous transaction completing
			@ (posedge HCLK);	// align with clock
			#1 HSIZE = size;	// set up signals for address phase, just after clock edge
			HTRANS = NONSEQ;	// transaction type non-sequential
			HWRITE = 1'b1;		// write transaction
			HADDR = addr;		// put address on bus
			HSELx = 1'b1;		// select this slave
			#1;	// a little later, store data for use in the data phase
			// write data must be aligned according to size and LSBs of address
			case ({size, addr[1:0]})
			  5'b000_00: 	nextWdata = data & 8'hff;  // byte write LSB
			  5'b000_01: 	nextWdata = (data & 8'hff) << 8;  // byte write next byte
			  5'b000_10: 	nextWdata = (data & 8'hff) << 16;  // byte write next byte
			  5'b000_11: 	nextWdata = (data & 8'hff) << 24;  // byte write MSB
			  5'b001_00: 	nextWdata = data & 16'hffff;  // half word write LSH
			  5'b001_10: 	nextWdata = (data & 16'hffff) << 16;  // half word write MSH
			  5'b010_00: 	nextWdata = data;  // word write
			  default:      nextWdata = 32'hdeadbeef;    // anything else is invalid
			endcase
		end
	endtask

// Task to simulate a read transaction on AHB Lite
	task AHBread (
			input [2:0] size,	// transaction width - BYTE, HALF or WORD
			input [31:0] addr,	// address
			input [31:0] data );	// expected data from slave
		begin  
			wait (HREADY == 1'b1);	// wait for ready signal - previous transaction completing
			@ (posedge HCLK);	// align with clock
			#1 HSIZE = size;	// set up signals for address phase, just after clock edge
			HTRANS = NONSEQ;	// transaction type non-sequential
			HWRITE = 1'b0;		// read transaction
			HADDR = addr;		// put address on bus
			HSELx = 1'b1;		// select this slave
			#1 expectRdata = data;	// a little later, store expected data for checking in the data phase
		end
	endtask

// Task to put bus in idle state after read or write transaction
	task AHBidle;
		begin  
			wait (HREADY == 1'b1); // wait for ready signal - previous transaction completing
			@ (posedge HCLK);	// then wait for clock edge
			#1 HTRANS = IDLE;	// set transaction type to idle
			HSELx = 1'b0;		// deselect the slave
		end
	endtask

// Control the HWDATA signal during the data phase
	always @ (posedge HCLK)
		if (~HRESETn) HWDATA <= 32'b0;
		else if (HSELx && HWRITE && HTRANS && HREADY) // our write transaction is moving to data phase
			#1 HWDATA <= nextWdata;	// change HWDATA shortly after the clock edge
		else if (HREADY)	// some other transaction in progress
			#1 HWDATA <= {HADDR[31:24], HADDR[11:0], 12'hbad}; // put rubbish on HWDATA

// Registers to hold expected read data during data phase, data size and position
// and a flag to indicate that read is in progress
	always @ (posedge HCLK)
		if (~HRESETn)
			begin
				rExpectRead <= 32'b0;
				rReadType <= 5'b0;
				checkRead <= 1'b0;
			end
		else if (HSELx && ~HWRITE && HTRANS && HREADY)  // our read transaction moving to data phase
			begin
			    // first update expected read register with expected data
				if (HSIZE == 3'b0) rExpectRead <= expectRdata & 8'hff;  // byte read
				else if (HSIZE == 3'b1) rExpectRead <= expectRdata & 16'hffff;  // half word read
				else rExpectRead <= expectRdata;	// word read (or larger, not supported)
				
				rReadType <= {HSIZE, HADDR[1:0]};  // also store size and address bits
				checkRead <= 1'b1;	// and set flag to get read data checked on next clock edge
			end
		else if (HREADY)	// some other transaction moving to data phase
				checkRead <= 1'b0;			// clear flag - no check needed

// Check the read data as the read transaction completes
// Error signal will be asserted for one cycle AFTER problem detected
	always @ (posedge HCLK)
		if (~HRESETn) error <= 1'b0;
		else if (checkRead & HREADY)	// our read transaction is completing on this clock edge
		  begin
		    case (rReadType)  // capture the appropriate data from the bus
			  5'b000_00: 	 readCapture = HRDATA & 8'hff;  // byte read LSB
              5'b000_01:     readCapture = (HRDATA >> 8) & 8'hff;  // byte read next byte
              5'b000_10:     readCapture = (HRDATA >> 16) & 8'hff;  // byte read next byte
              5'b000_11:     readCapture = (HRDATA >> 24) & 8'hff;  // byte read MSB
              5'b001_00:     readCapture = HRDATA & 16'hffff;       // half word read LSH
              5'b001_10:     readCapture = (HRDATA >> 16) & 16'hffff; // half word read MSH
              default:       readCapture = HRDATA;  // word read (anything else is invalid)
            endcase
            
            // compare captured data with expected read data
			if (readCapture != rExpectRead)	// the captured data is not as expected
				begin
					error <= 1'b1;		// so flag this as an error
					errCount = errCount + 1;	// and increment the error counter
				end
			else error <= 1'b0;			// otherwise our read transaction is OK
		  end  // end checking our read transaction
		  
		else		// this is some other transaction 
			error <= 1'b0;	// so no error
			
// Control the HREADY signal during the data phase
	always @ (posedge HCLK)
		if (~HRESETn) transState <= 1'b0;	// after reset, this is not the data phase of our transaction
		else if (HSELx && HTRANS && HREADY) // transaction with this slave is moving to data phase
			#1 transState <= 1'b1;			// so this slave controls HREADY
		else if (HREADY)					// idle, or some other transaction is moving to data phase
			#1 transState <= 1'b0;			// some other slave controls HREADY
			
	assign HREADY = transState ? HREADYOUT : 1'b1;     // other slave is always ready

//============================= END of AHB bus tasks =========================================
