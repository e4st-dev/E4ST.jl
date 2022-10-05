function save_mpc(casename)
[mpc, offer, contab] = feval(casename);


gen = array2table(...
    mpc.gen(:, [1, 8, 2, 9, 10]), 'VariableNames', ...
    {'bus_id', 'status', 'gen', 'gen_max', 'gen_min'}...
);
   
gen.cost_variable = mpc.gencost(:, 5);
gen.cost_fixed = offer(:,1); % Update for DAC/DL

% Make bus table
bus = array2table(...
    mpc.bus(:, [1, 2, 9, 10]), 'VariableNames', ...
    {'bus_id', 'bus_type', 'v_angle', 'v_base'}...
);

% Make branch table
branch = array2table(...
    mpc.branch(:, [1, 2, 11, 5, 6, 7, 8]), 'VariableNames', ...
    {'f_bus_id', 't_bus_id', 'status', 'b', 'rate_a', 'rate_b', 'rate_c'}...
);

% TODO: Possibly split DL and DAC?
% TODO: Save things
mkdir(casename)
writetable(gen, [casename, filesep, 'gen.csv']);
writetable(bus, [casename, filesep, 'bus.csv']);
writetable(branch, [casename, filesep, 'branch.csv']);

end


