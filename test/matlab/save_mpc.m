function save_mpc(casename)
[mpc, offer, contab] = feval(casename);


gen = array2table(...
    mpc.gen(:, [1, 8, 10, 9]), 'VariableNames', ...
    {'bus_idx', 'status', 'pcap_min', 'pcap_max'}...
);
   
gen.vom = mpc.gencost(:, 5);
gen.fom = offer(:,1)./2; % Update for DAC/DL
gen.capex = gen.fom;

% Make bus table
bus = array2table(...
    mpc.bus(:, [1, 2, ]), 'VariableNames', ...
    {'bus_idx', 'bus_type'}...
);
bus.load = 0

% Make branch table
branch = array2table(...
    mpc.branch(:, [1, 2, 11, 5, 6]), 'VariableNames', ...
    {'f_bus_idx', 't_bus_idx', 'status', 'x', 'pf_max'}...
);

% TODO: Possibly split DL and DAC?
% TODO: Save things
mkdir(casename)
writetable(gen, [casename, filesep, 'gen.csv']);
writetable(bus, [casename, filesep, 'bus.csv']);
writetable(branch, [casename, filesep, 'branch.csv']);

end


