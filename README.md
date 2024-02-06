# LTspiceFromMATLAB

Automate LTspice simulation and analysis in MATLAB
 
## Requirements

 - MATLAB
 - LTspice
 - Windows (should work on other OS with slight modifications)
 
## What does this do?

This repo contains example code showing how to automate LTspice simulations in MATLAB, where the MATLAB script edits the SPICE variable values from a template netlist and runs the simulation automatically. The results are imported for processing and visualisation.

The included example is a simple double pulse test where the gate resistance and source inductance are swept through.

## How does it work?

In `LTspiceLAB.m`, the file paths for the netlists and LTspice executable are configured. The script uses a template netlist `DPTtemplate.net` which is modified by the script and saved to `DPTauto.net`. A regular expression looks for a `.param` statement, where the writable variables are defined.

The script iterates through the parameter space, overwriting the netlist file each time with new values. LTspice is run using the `dos()` function, it is allowed to run and then the results are imported using `LTspice2Matlab.m` (which I did not write myself).

The data is placed into a table to make it easier to view and manipulate. It can be processed and analysed in the script to produce a set of values placed in the `output` struct. An array of these structs are saved, forming the output dataset.

## Limitations

This script is very slow and strictly **serial**. The main timewaster is opening LTspice for each and every point in the parameter space. For instance, a 20x20x20 simulation (8000 points) took around 10 hours on my PC (Ryzen 5 3600 + NVMe). It writes the netlist to the same filepath each time, calling the LTspice executable and killing the process using a method that kills all running instances. While it would benefit greatly from parallelisation, this is simply not possible without work that I do not have the time for.

## Authorship

### LTspice2Matlab
 - Copyright (c) 2009, Paul Wagner
 - Copyright (c) 2019, Peter Feichtinger
 - Source available on GitHub: https://github.com/PeterFeicht/ltspice2matlab

 
### Everything else
 - Copyright (c) 2024, David Way
 - Used in final year project as part of MEng Electronic and Electrical Engineering degree
