//=============================================================================
// Sequencer: qspi_sequencer
// Purpose:   Parameterized sequencer for qspi_transaction items. Routes
//            sequence items from virtual sequences to the QSPI driver.
//=============================================================================
class qspi_sequencer extends qspi_sequencer#(qspi_transaction);
  `qspi_component_utils(qspi_sequencer)

  function new(string name, qspi_component parent);
    super.new(name, parent);
  endfunction
endclass
