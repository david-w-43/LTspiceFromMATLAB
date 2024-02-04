%% Set file paths, edit these

% Working directory where the files are located, currently set as MATLAB directory
workingDir = pwd;

% Template netlist, which will be modified by the code
templateName = "DPTtemplate.net";

% Location where modified netlist is saved
modifiedNetlistName = "DPTauto.net";

% Executable
spiceExecutable = "C:\Program Files\LTC\LTspiceXVII\XVIIx64.exe";

%% Generated file paths, do not edit these
templatePath = workingDir + "\" + templateName;
modifiedNetlistPath = workingDir + "\" + modifiedNetlistName;

%% Define constant variables for circuit
Vdc = 24;

% Variables to iterate
gateResistances    = logspace(0, 2, 5);
sourceInductances  = logspace(-9, -7, 5);

%% Preallocate results?
% Results for each run are stored in a struct

output.Rg = NaN;
output.Ls = NaN;
output.VgsPeak = NaN;
output.EnergyLoss = NaN;

results = repmat(output, length(gateResistances), length(sourceInductances));


%% Iterate through values
counter = 0;
elapsed = zeros(1, numel(results));
for i = 1:length(gateResistances)
    for j = 1:length(sourceInductances)
        tic;

        %% Open file, read and modify netlist
        netlist = fileread(templatePath);
        
        % Set variables for this run from the list
        Rg = gateResistances(i); 
        Ls = sourceInductances(j);

        % Save 
        output.Ls = Ls;
        output.Rg = Rg;

        % Calculate time remaining
        timeRemaining = seconds((numel(results) - counter)*mean(elapsed(1:counter)));
        timeRemaining.Format = "hh:mm:ss";

        % Print values to display to keep track
        fprintf("%.2f%%: Rg=%.3E, Ls=%.3E - %s remaining \n", ...
            100*counter/numel(results), ...
            Rg, Ls, timeRemaining);

        % Increment counter for display
        counter = counter + 1;
        
        % Modify netlist
        netlist = setValue(netlist, "Rg",       Rg      );
        netlist = setValue(netlist, "Ls",       Ls      );
        
        %% Write netlist to file
        % Get around fprintf's formatting by escaping the escape chars :)
        netlist = strrep(netlist, "\", "\\");
        

        % Open and write to file
        fileID = -1;
        while (fileID == -1) % Ensure the file gets opened properly
            fileID = fopen(modifiedNetlistPath, "w");
            if (fileID == -1)
                pause(1);
            end
        end

        fprintf(fileID, netlist);
        fclose(fileID);
        
    %% Run spice and Read data    
    try       

        % Results filename
        [~, name, ~] = fileparts(modifiedNetlistPath);
        resultsFilename = name + ".raw";

        raw_data = spiceHandler(modifiedNetlistPath, resultsFilename, spiceExecutable, 1.3);
        
        while exist(resultsFilename, "file") == 2
            try
                % Rename data file so we can keep track of when a new one is
                % generated
                movefile(resultsFilename, resultsFilename + "old");
            catch 
                pause(0.1);
            end
        end

        if (raw_data.time_vect(end) < 5E-6) % If simulation hasn't completed
            % Rerun the simulation with more time
            raw_data = spiceHandler(modifiedNetlistPath, resultsFilename, spiceExecutable, 5);
        end

        % Check again, throw error if failed
        if (raw_data.time_vect(end) < 5E-6)
            throw(MException("Sim:Incomplete", "Simulation did not complete"));
        end

        
        %% Create table for easier analysis
        % Good idea to skip duplicate currents for components in series
        % This is cumbersome and should be updated if the netlist ever changes. 
        % Not strictly necessary as the imported data is in a usable
        % format anyway

        dataTable = table(...
            raw_data.time_vect', ...            % Time
            raw_data.variable_mat(02,:)', ...   % Vd
            raw_data.variable_mat(03,:)', ...   % Vg
            raw_data.variable_mat(04,:)', ...   % Vs
            raw_data.variable_mat(06,:)', ...   % Id
            'VariableNames', [cellstr("time") raw_data.variable_name_list([2:4 6])]);
        
        %% Now do some data processing :)

        % Energy loss in transistor. This is crude, doesn't find
        % switching locations or anything but this is just a demo
        output.EnergyLoss = trapz(dataTable.time, abs((dataTable.("V(vd)")-dataTable.("V(vs)")) .* dataTable.("Id(M1)")));
        
        % Get peak Vgs
        Vgs = dataTable.("V(vg)") - dataTable.("V(vs)");
        output.VgsPeak = max(Vgs, [], 'all');

        % Find rise/fall times etc, left as an exercise for the reader

        % Errors may occur if processing requires finding an event that
        % does not occur in a particular test. This must be handled
        % gracefully.
        catch ex 
            disp("Error! Line " + ex.stack(end).line + ": "  + ex.identifier);
            
            output.VgsPeak = NaN;
            output.EnergyLoss = NaN;
        end
        
        % Save results!
        results(i, j) = output;

        elapsed(counter) = toc;

    end % Ls

    % Save results at end of every innermost loop
    save("results.mat", "results", "gateResistances", "sourceInductances");

end % Rg

totalTime = seconds(sum(elapsed));
totalTime.Format = 'hh:mm:ss';
fprintf("\n\nDone in %s!\n\n", totalTime);

%% Display findings

% Now that the parameter space has been fully explored, it's time to plot
% some results

GatePeakVoltages = reshape([results.VgsPeak], size(results, 1), size(results, 2));
figure(1); surf(sourceInductances, gateResistances, GatePeakVoltages);
title("Peak V_{gs}");
ylabel("Gate Resistance");
xlabel("Source Inductance");
zlabel("Maximum V_{gs}");
xscale("log");
yscale("log");

EnergyLoss = reshape([results.EnergyLoss], size(results, 1), size(results, 2));
figure(2); surf(sourceInductances, gateResistances, EnergyLoss);
title("Energy lost in MOSFET");
ylabel("Gate Resistance");
xlabel("Source Inductance");
zlabel("Total energy");
xscale("log");
yscale("log");

% This time with interpolation
[xx, yy] = meshgrid(logspace(-9,-7,50), logspace(0,2,50));
EnergyLossInterp = interp2(sourceInductances, gateResistances, EnergyLoss, ...
    xx, yy, "linear");
figure(3); surf(xx, yy, EnergyLossInterp);
title("Interpolated energy loss");
ylabel("Gate Resistance");
xlabel("Source Inductance");
zlabel("Total energy");
xscale("log");
yscale("log");


%% Functions!

% Handles SPICE
function raw_data = spiceHandler(netlistPath, resultsFilename, executable, delay)
    % Get executable name
    [~, exeName, ~] = fileparts(executable);

    % Run simulation
    runSPICE(executable, netlistPath);

    % Wait until output file exists
    while exist(resultsFilename, "file") ~= 2
        pause(0.1);
    end
    pause(delay);

    % End LTspice processes
    taskkill(exeName + ".exe");

    % Import the data
    raw_data = LTspice2Matlab(resultsFilename);
end

% Sends command to run sim on specified netlist
function runSPICE(executable, netlistPath)    
    % Command
    cmd = "start " + '"' + executable + " -b"+ '"' + ' ' + '"' + netlistPath + '"';
    
    % Execute
    dos(cmd);
end

% Sends command to kill executable
function taskkill(exeName)

    cmd = "taskkill /IM " + exeName;

    [~, ~] = dos(cmd);
end

% Set the variable with specified name to the specified value
% Assumes the variable is set in a .param statement
% Input:    whole netlist as string
%           name of variable as string
%           value as (real) number
% Output:   whole modified netlist as string
function outputNetlist = setValue(inputNetlist, name, value)
    % Get the position in the netlist of the value of the specified
    % variable
    regexQuery = sprintf("(?<=\\.param.*\\s%s=)(\\d+(\\.\\d+)?)(Meg|Mil|[TGKfpnuM])?(?=\\s)", name);
    
    % Set the value in the netlist, in scientific notation
    outputNetlist = regexprep(inputNetlist, regexQuery, num2str(value, "%E"));

    % Convert to string
    outputNetlist = convertCharsToStrings(outputNetlist);
end