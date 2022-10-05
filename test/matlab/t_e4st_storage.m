function t_e4st_storage(quiet)
%t_e4st_storage  Tests the storage component of e4st_solve
%
%   Includes a two bus system with a battery.

%   E4ST
%   Copyright (c) 2009-2017 by Power System Engineering Research Center (PSERC)
%   by Ray Zimmerman, PSERC Cornell
%
%   This file is part of E4ST.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See http://e4st.com/ for more info.

if nargin < 1
    quiet = 0;
end

n_testcases = 3;
n_tests = 27;

t_begin(n_tests * n_testcases, quiet);

%% options
mpopt = mpoption('verbose', 0, 'out.all', 0);
% mpopt = mpoption('verbose', 2, 'out.all', -1);
mpopt = mpoption(mpopt, 'opf.violation', 5e-8, 'mips.comptol', 1e-16, 'mips.step_control', 0);

%% solver options
if have_fcn('cplex')
    %mpopt = mpoption(mpopt, 'cplex.lpmethod', 0);       %% automatic
    %mpopt = mpoption(mpopt, 'cplex.lpmethod', 1);       %% primal simplex
    mpopt = mpoption(mpopt, 'cplex.lpmethod', 2);       %% dual simplex
    %mpopt = mpoption(mpopt, 'cplex.lpmethod', 3);       %% network simplex
    %mpopt = mpoption(mpopt, 'cplex.lpmethod', 4);       %% barrier
    mpopt = mpoption(mpopt, 'cplex.opts.mip.tolerances.mipgap', 0);
    mpopt = mpoption(mpopt, 'cplex.opts.mip.tolerances.absmipgap', 0);
    mpopt = mpoption(mpopt, 'cplex.opts.threads', 2);
end
if have_fcn('glpk')
    mpopt = mpoption(mpopt, 'glpk.opts.mipgap', 0);
    mpopt = mpoption(mpopt, 'glpk.opts.tolint', 1e-10);
    mpopt = mpoption(mpopt, 'glpk.opts.tolobj', 1e-10);
end
if have_fcn('gurobi')
    %mpopt = mpoption(mpopt, 'gurobi.method', -1);       %% automatic
    %mpopt = mpoption(mpopt, 'gurobi.method', 0);        %% primal simplex
    mpopt = mpoption(mpopt, 'gurobi.method', 1);        %% dual simplex
    %mpopt = mpoption(mpopt, 'gurobi.method', 2);        %% barrier
    mpopt = mpoption(mpopt, 'gurobi.threads', 2);
    mpopt = mpoption(mpopt, 'gurobi.opts.MIPGap', 0);
    mpopt = mpoption(mpopt, 'gurobi.opts.MIPGapAbs', 0);
end
if have_fcn('mosek')
    sc = mosek_symbcon;
    %mpopt = mpoption(mpopt, 'mosek.lp_alg', sc.MSK_OPTIMIZER_FREE);            %% default
    %mpopt = mpoption(mpopt, 'mosek.lp_alg', sc.MSK_OPTIMIZER_INTPNT);          %% interior point
    %mpopt = mpoption(mpopt, 'mosek.lp_alg', sc.MSK_OPTIMIZER_PRIMAL_SIMPLEX);  %% primal simplex
    mpopt = mpoption(mpopt, 'mosek.lp_alg', sc.MSK_OPTIMIZER_DUAL_SIMPLEX);     %% dual simplex
    %mpopt = mpoption(mpopt, 'mosek.lp_alg', sc.MSK_OPTIMIZER_FREE_SIMPLEX);    %% automatic simplex
    %mpopt = mpoption(mpopt, 'mosek.opts.MSK_DPAR_MIO_TOL_X', 0);
    mpopt = mpoption(mpopt, 'mosek.opts.MSK_IPAR_MIO_NODE_OPTIMIZER', sc.MSK_OPTIMIZER_DUAL_SIMPLEX);
    mpopt = mpoption(mpopt, 'mosek.opts.MSK_IPAR_MIO_ROOT_OPTIMIZER', sc.MSK_OPTIMIZER_DUAL_SIMPLEX);
    mpopt = mpoption(mpopt, 'mosek.opts.MSK_DPAR_MIO_TOL_ABS_RELAX_INT', 1e-9);
    %mpopt = mpoption(mpopt, 'mosek.opts.MSK_DPAR_MIO_TOL_REL_RELAX_INT', 0);
    mpopt = mpoption(mpopt, 'mosek.opts.MSK_DPAR_MIO_TOL_REL_GAP', 0);
    mpopt = mpoption(mpopt, 'mosek.opts.MSK_DPAR_MIO_TOL_ABS_GAP', 0);
end
if have_fcn('intlinprog')
    %mpopt = mpoption(mpopt, 'linprog.Algorithm', 'interior-point');
    %mpopt = mpoption(mpopt, 'linprog.Algorithm', 'active-set');
    %mpopt = mpoption(mpopt, 'linprog.Algorithm', 'simplex');
    mpopt = mpoption(mpopt, 'linprog.Algorithm', 'dual-simplex');
    %mpopt = mpoption(mpopt, 'intlinprog.RootLPAlgorithm', 'primal-simplex');
    mpopt = mpoption(mpopt, 'intlinprog.RootLPAlgorithm', 'dual-simplex');
    mpopt = mpoption(mpopt, 'intlinprog.TolCon', 1e-9);
    mpopt = mpoption(mpopt, 'intlinprog.TolGapAbs', 0);
    mpopt = mpoption(mpopt, 'intlinprog.TolGapRel', 0);
    mpopt = mpoption(mpopt, 'intlinprog.TolInteger', 1e-6);
end

% mpopt = mpoption(mpopt, 'sopf.force_Pc_eq_P0', 1);  %% constrain contracted == base case dispatch
mpopt = mpoption(mpopt, 'model', 'DC');

if have_fcn('gurobi')
    slvr = 'GUROBI';
elseif have_fcn('cplex')
    slvr = 'CPLEX';
elseif have_fcn('mosek')
    slvr = 'MOSEK';
elseif have_fcn('linprog_ds')
    slvr = 'OT';
elseif have_fcn('glpk')
    slvr = 'GLPK';
elseif have_fcn('linprog')
    slvr = 'OT';
else
    slvr = 'MIPS';
end
% slvr = 'BPMPD';
% slvr = 'CLP';
% slvr = 'CPLEX';
% slvr = 'GLPK';
% slvr = 'GUROBI';
% slvr = 'IPOPT';
% slvr = 'MOSEK';
% slvr = 'OT';
% slvr = 'MIPS';
mpopt = mpoption(mpopt, 'opf.dc.solver', slvr);

%% turn off warnings
if have_fcn('octave')
    if have_fcn('octave', 'vnum') >= 4
        file_in_path_warn_id = 'Octave:data-file-in-path';
    else
        file_in_path_warn_id = 'Octave:load-file-in-path';
    end
    s1 = warning('query', file_in_path_warn_id);
    warning('off', file_in_path_warn_id);
end
s7 = warning('query', 'MATLAB:nearlySingularMatrix');
s6 = warning('query', 'MATLAB:nearlySingularMatrixUMFPACK');
warning('off', 'MATLAB:nearlySingularMatrix');
warning('off', 'MATLAB:nearlySingularMatrixUMFPACK');

%% define named indices into data matrices
[PQ, PV, REF, NONE, BUS_I, BUS_TYPE, PD, QD, GS, BS, BUS_AREA, VM, ...
    VA, BASE_KV, ZONE, VMAX, VMIN, LAM_P, LAM_Q, MU_VMAX, MU_VMIN] = idx_bus;
[GEN_BUS, PG, QG, QMAX, QMIN, VG, MBASE, GEN_STATUS, PMAX, PMIN, ...
    MU_PMAX, MU_PMIN, MU_QMAX, MU_QMIN, PC1, PC2, QC1MIN, QC1MAX, ...
    QC2MIN, QC2MAX, RAMP_AGC, RAMP_10, RAMP_30, RAMP_Q, APF] = idx_gen;
[F_BUS, T_BUS, BR_R, BR_X, BR_B, RATE_A, RATE_B, RATE_C, ...
    TAP, SHIFT, BR_STATUS, PF, QF, PT, QT, MU_SF, MU_ST, ...
    ANGMIN, ANGMAX, MU_ANGMIN, MU_ANGMAX] = idx_brch;
[CT_LABEL, CT_PROB, CT_TABLE, CT_TBUS, CT_TGEN, CT_TBRCH, CT_TAREABUS, ...
    CT_TAREAGEN, CT_TAREABRCH, CT_ROW, CT_COL, CT_CHGTYPE, CT_REP, ...
    CT_REL, CT_ADD, CT_NEWVAL, CT_TLOAD, CT_TAREALOAD, CT_LOAD_ALL_PQ, ...
    CT_LOAD_FIX_PQ, CT_LOAD_DIS_PQ, CT_LOAD_ALL_P, CT_LOAD_FIX_P, ...
    CT_LOAD_DIS_P, CT_TGENCOST, CT_TAREAGENCOST, CT_MODCOST_F, ...
    CT_MODCOST_X] = idx_ct;
c = idx_dcline;

if have_fcn('glpk') || have_fcn('gurobi') || have_fcn('cplex') || ...
        have_fcn('mosek') || have_fcn('linprog') ||  have_fcn('clp') || ...
        have_fcn('ipopt')


    %% load the case
    for testnum = 1:n_testcases
        casename = sprintf('t_case_e4st_storage%d', testnum);
        solution = sprintf('t_e4st_storage_soln%d', testnum);
    %     [mpc, roffer, contab] = loadcase(casename);
        [mpc, roffer, contab] = feval(casename);
        mpc = loadcase(mpc);
        ng = size(mpc.gen, 1);
        ig = find(~isload(mpc.gen));


        %% force active contracts to zero, expected for e4st_solve()
        roffer = e4st_offer2mat(roffer, ng);
        roffer(:, 11:12) = 0;

        [results, f, success, info, et] = ...
                        e4st_solve(mpc, roffer, contab, mpopt);
       %-------save\load solution--------------------
%         save(solution, 'f', 'results');
        s = load(solution);
       %-------table of hourly generation-----------------
        nh = size(unique(contab(:,1)),1) + 1;
        ng = size(mpc.gen,1);
        nb = size(mpc.bus,1);
        gen_hourly = zeros(ng, nh);
        lmp_hourly = zeros(nb, nh);
        prob = unique(contab(:, 1:2),'rows');
        prob = [prob; 0, 1 - sum(prob(:,2))];
        for i = 1:nh
            probability = prob(prob(:,1) == i -1, 2);
            if i == 1
                gen_hourly(:, i) = results.base.gen(:,PG);
                lmp_hourly(:, i) = results.base.bus(:, LAM_P)/probability;
            else
                gen_hourly(:, i) = results.cont(i-1).gen(:,PG);
                lmp_hourly(:, i) = results.cont(i-1).bus(:, LAM_P)/probability;
            end    
        end    



        %%-----  test the results  -----
        t = 'success';
        t_ok(success, t);

        t = 'f';
        t_is(f, s.f, 5, t);

        t = 'results.energy.Pc';
        t_is(results.energy.Pc, s.results.energy.Pc, 5, t);

        t = 'results.energy.Gmax';
        t_is(results.energy.Gmax, s.results.energy.Gmax, 5, t);

        t = 'results.energy.Gmin';
        t_is(results.energy.Gmin, s.results.energy.Gmin, 5, t);

        t = 'results.energy.Qmax';
        t_is(results.energy.Qmax, s.results.energy.Qmax, 5, t);

        t = 'results.energy.Qmin';
        t_is(results.energy.Qmin, s.results.energy.Qmin, 5, t);

        t = 'results.energy.sum_muPmax';
        t_is(results.energy.sum_muPmax, s.results.energy.sum_muPmax, 5, t);

        t = 'results.energy.sum_muPmin';
        t_is(results.energy.sum_muPmin, s.results.energy.sum_muPmin, 5, t);

        t = 'results.energy.prc.sum_bus_lam_p';
        t_is(results.energy.prc.sum_bus_lam_p, s.results.energy.prc.sum_bus_lam_p, 5, t);

        t = 'results.energy.prc.sum_bus_lam_q';
        t_is(results.energy.prc.sum_bus_lam_q, s.results.energy.prc.sum_bus_lam_q, 5, t);

        t = 'results.energy.mu.alphaP';
        t_is(results.energy.mu.alphaP, s.results.energy.mu.alphaP, 5, t);

        kp = find(results.reserve.qty.Rp_pos);

        t = 'results.reserve.mu.Rp_pos';
        t_is(sum(results.reserve.mu.Rp_pos(kp, :), 2), sum(s.results.reserve.mu.Rp_pos(kp, :), 2), 5, t);

        t = 'results.reserve.mu.Rp_neg';
        t_is(sum(results.reserve.mu.Rp_neg, 2), sum(s.results.reserve.mu.Rp_neg, 2), 5, t);

        t = 'results.reserve.qty.Rp_pos(ig)';
        t_is(results.reserve.qty.Rp_pos(ig), s.results.reserve.qty.Rp_pos(ig), 5, t);

        t = 'results.reserve.qty.Rp_neg';
        t_is(results.reserve.qty.Rp_neg, s.results.reserve.qty.Rp_neg, 5, t);

        t = 'results.reserve.prc.Rp_pos';
        t_is(results.reserve.prc.Rp_pos(kp), s.results.reserve.prc.Rp_pos(kp), 5, t);

        t = 'results.reserve.prc.Rp_neg';
        t_is(results.reserve.prc.Rp_neg, s.results.reserve.prc.Rp_neg, 5, t);

    %     t = 'results.opf_results.x';
    %     t_is(results.opf_results.x, s.results.opf_results.x, 6, t);

        t = 'results.short_term_storage.s0';
        t_is(results.short_term_storage.s0, s.results.short_term_storage.s0, 8, t);

        %% base case quantities
        t = 'results.base.bus(:, VA)';
        t_is(results.base.bus(:, VA), s.results.base.bus(:, VA), 6, t);

        t = 'results.base.gen(:, PG)';
        t_is(results.base.gen(:, PG), s.results.base.gen(:, PG), 6, t);

    % [results.base.if.P results.base.if.mu.l results.base.if.mu.u]

        %% contingency quantities
        nc = length(results.cont);
        for k = 1:nc
            p = 6;
            t = sprintf('results.cont(%d).bus(:, VA)', k);
            t_is(results.cont(k).bus(:, VA), s.results.cont(k).bus(:, VA), p, t);

            t = sprintf('results.cont(%d).gen(:, PG)', k);
            t_is(results.cont(k).gen(:, PG), s.results.cont(k).gen(:, PG), p, t);
        end

    end
else
    t_skip(n_tests, 'no adequate LP solver available');
end

%% turn warnings back on
if have_fcn('octave')
    warning(s1.state, file_in_path_warn_id);
end
warning(s7.state, 'MATLAB:nearlySingularMatrix');
warning(s6.state, 'MATLAB:nearlySingularMatrixUMFPACK');

t_end;
